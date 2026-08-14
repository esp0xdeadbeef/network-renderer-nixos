#!/usr/bin/env python3
"""Materialize one protected reservation identity set into runtime Kea + DNS.

GAMP-ID: FS-970-HDS-010-SDS-010-SMS-010 / SMS-020 / SMS-040
GAMP-SCOPE: software-module-construction

Runtime counterpart of the SDS-010 "compose public assignment fields with a
protected-source fragment by stable endpoint handle" contract.

The protected source is a site-independent identity registry:

    [ { "id": "l-portal-usb", "mac": "aa:bb:cc:dd:ee:01" },
      { "id": "idrac-m780", "mac": "...", "hostname": "idrac-m780" },
      { "id": "test-raspi", "duid": "...", "iid": "...", "hostname": "test-raspi" } ]

Hostname is optional and secret when present (per-entry).  The public
assignment side arrives in the Kea template as reservations carrying a
"reservation-handle" marker plus the already-resolved address:

    { "hw-address": "", "ip-address": "10.2.8.100", "reservation-handle": "l-portal-usb" }

This materializer joins the two on the handle, fills the selected matcher
(MAC for IPv4, DUID for IPv6), and fails closed on duplicate or missing
identity.  Hostname may be supplied by exactly one of the two sources.
"""

from __future__ import annotations

import argparse
import grp
import ipaddress
import json
import os
from pathlib import Path
import re
import sys
import tempfile
from typing import Any


DIAGNOSTIC = "diagnostic.runtime-reservation-secret-record-invalid"
PUBLICATION_HOSTNAME_MISSING = "diagnostic.protected-reservation-name-publication-hostname-missing"
CROSS_IDENTITY_MISMATCH = "diagnostic.protected-reservation-cross-identity-mismatch"
HANDLE_FIELD = "reservation-handle"
SCHEMA_FIELDS = {"id", "mac", "duid", "iid"}
HOSTNAME = re.compile(r"^[A-Za-z0-9][A-Za-z0-9._-]*$")
MAC = re.compile(r"^(?:[0-9A-Fa-f]{2}:){5}[0-9A-Fa-f]{2}$")
IID = re.compile(r"^[0-9A-Fa-f]{16}$")
DUID = re.compile(r"^[0-9A-Fa-f]{4,260}$")
DNS_RECORD_CLASSES = {"A", "AAAA", "PTR"}
DNS_NAMESPACE = re.compile(r"^(?:[A-Za-z0-9][A-Za-z0-9_-]*\.)+$")


class ReservationContractError(Exception):
    """A protected source failed the redacted runtime contract."""


def require(condition: bool) -> None:
    if not condition:
        raise ReservationContractError


def normalized_duid(value: object) -> str:
    require(isinstance(value, str))
    compact = value.replace(":", "").replace("-", "")
    require(len(compact) % 2 == 0 and DUID.fullmatch(compact) is not None)
    return ":".join(
        compact[index : index + 2].lower() for index in range(0, len(compact), 2)
    )


def load_registry(source_path: Path) -> dict[str, dict[str, Any]]:
    """Read the protected identity registry keyed by stable endpoint handle."""
    with source_path.open("r", encoding="utf-8") as source_handle:
        source = json.load(source_handle)
    require(isinstance(source, list) and len(source) > 0)

    registry: dict[str, dict[str, Any]] = {}
    for record in source:
        require(isinstance(record, dict))
        require(set(record).issubset(SCHEMA_FIELDS))
        handle = record.get("id")
        require(isinstance(handle, str) and handle != "" and handle not in registry)
        registry[handle] = record
    return registry


def identity_for_record(family: str, record: dict[str, Any]) -> tuple[str, str | None]:
    """Return (matcher-kind, normalized-identity) for the selected family."""
    if family == "ipv4":
        mac = record.get("mac")
        require(isinstance(mac, str) and MAC.fullmatch(mac) is not None)
        return ("hw-address", mac.lower())
    duid = record.get("duid")
    require(isinstance(duid, str))
    normalized = normalized_duid(duid)
    iid = record.get("iid")
    if iid is not None:
        require(
            isinstance(iid, str)
            and IID.fullmatch(iid.replace(":", "").replace("-", "")) is not None
        )
    return ("duid", normalized)


def materialize_dns_lines(
    namespace: str,
    record_classes: list[str],
    family: str,
    records: list[dict[str, Any]],
) -> tuple[list[str], set[str]]:
    require(DNS_NAMESPACE.fullmatch(namespace) is not None)
    require(record_classes and set(record_classes).issubset(DNS_RECORD_CLASSES))
    require(len(record_classes) == len(set(record_classes)))
    require(family in {"ipv4", "ipv6"})

    lines: list[str] = ["server:"]
    records_by_name: dict[str, dict[int, set[str]]] = {}
    address_owners: dict[str, str] = {}
    dns_ids: set[str] = set()
    for record in records:
        hostname = record.get("hostname")
        if not isinstance(hostname, str) or not hostname:
            raise ReservationContractError(PUBLICATION_HOSTNAME_MISSING)
        require(HOSTNAME.fullmatch(hostname) is not None and "." not in hostname)
        fqdn = f"{hostname}.{namespace}"
        normalized_fqdn = fqdn.lower()
        name_records = records_by_name.setdefault(
            normalized_fqdn,
            {4: set(), 6: set()},
        )

        if family == "ipv4":
            address = record.get("ip-address")
            require(isinstance(address, str))
            addresses = [address]
        else:
            addresses = record.get("ip-addresses")
            require(isinstance(addresses, list) and len(addresses) >= 1)

        for address in addresses:
            parsed = ipaddress.ip_address(address)
            previous_owner = address_owners.get(address)
            require(previous_owner is None or previous_owner == normalized_fqdn)
            address_owners[address] = normalized_fqdn
            name_records[parsed.version].add(address)

    for normalized_fqdn in sorted(records_by_name):
        name_records = records_by_name[normalized_fqdn]
        for version, record_class in ((4, "A"), (6, "AAAA")):
            ordered_addresses = sorted(
                name_records[version],
                key=lambda value: int(ipaddress.ip_address(value)),
            )
            for address in ordered_addresses:
                if record_class in record_classes:
                    lines.append(
                        f'  local-data: "{normalized_fqdn} IN {record_class} {address}"'
                    )
                if "PTR" in record_classes:
                    lines.append(
                        f'  local-data-ptr: "{address} {normalized_fqdn}"'
                    )

    return (lines, dns_ids)


def insert_reservations(
    config: dict[str, Any],
    family: str,
    source_path: Path,
    has_out_of_pool: bool,
) -> tuple[dict[str, Any], list[dict[str, Any]]]:
    if family == "ipv4":
        subnets = config["Dhcp4"]["subnet4"]
        identity_key = "hw-address"
    else:
        subnets = config["Dhcp6"]["subnet6"]
        identity_key = "duid"

    registry = load_registry(source_path)
    require(isinstance(subnets, list) and len(subnets) == 1)
    existing = subnets[0].get("reservations", [])
    require(isinstance(existing, list))

    resolved: list[dict[str, Any]] = []
    seen_identities: set[str] = set()
    seen_addresses: set[str] = set()
    for record in existing:
        require(isinstance(record, dict))
        if HANDLE_FIELD not in record:
            # Inline public reservation; keep it but still enforce uniqueness.
            identity = record.get(identity_key)
            address = (
                record.get("ip-address")
                if family == "ipv4"
                else (record.get("ip-addresses") or [None])[0]
            )
            if identity is not None and address is not None:
                require(identity not in seen_identities and address not in seen_addresses)
                seen_identities.add(identity)
                seen_addresses.add(str(address))
            resolved.append(record)
            continue

        handle = record.pop(HANDLE_FIELD)
        protected = registry.get(handle)
        require(
            protected is not None,
            f"{CROSS_IDENTITY_MISMATCH}: assignment handle '{handle}' has no protected identity",
        )
        kind, identity = identity_for_record(family, protected)
        require(identity not in seen_identities)
        seen_identities.add(identity)

        if family == "ipv4":
            address = record.get("ip-address")
            require(isinstance(address, str))
            record[kind] = identity
            require(address not in seen_addresses)
            seen_addresses.add(address)
        else:
            addresses = record.get("ip-addresses")
            require(isinstance(addresses, list) and len(addresses) == 1)
            require(str(addresses[0]) not in seen_addresses)
            seen_addresses.add(str(addresses[0]))
            record[kind] = identity

        # Hostname is a public assignment field only; the registry carries no
        # hostname, so there is no conflict to resolve.
        resolved.append(record)

    subnets[0]["reservations"] = resolved
    subnets[0]["reservations-in-subnet"] = True
    subnets[0]["reservations-out-of-pool"] = has_out_of_pool
    return (config, resolved)


def atomic_write(path: Path, value: dict[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True, mode=0o700)
    descriptor, temporary_name = tempfile.mkstemp(prefix=".kea-", dir=path.parent)
    temporary_path = Path(temporary_name)
    try:
        os.fchmod(descriptor, 0o600)
        with os.fdopen(descriptor, "w", encoding="utf-8") as output_handle:
            json.dump(value, output_handle, separators=(",", ":"), sort_keys=True)
            output_handle.write("\n")
            output_handle.flush()
            os.fsync(output_handle.fileno())
        os.replace(temporary_path, path)
    except Exception:
        temporary_path.unlink(missing_ok=True)
        raise


def atomic_write_dns(path: Path, lines: list[str], group_name: str) -> None:
    group_id = grp.getgrnam(group_name).gr_gid
    path.parent.mkdir(parents=True, exist_ok=True, mode=0o750)
    os.chmod(path.parent, 0o750)
    os.chown(path.parent, -1, group_id)
    descriptor, temporary_name = tempfile.mkstemp(prefix=".dns-", dir=path.parent)
    temporary_path = Path(temporary_name)
    try:
        os.fchmod(descriptor, 0o640)
        os.fchown(descriptor, -1, group_id)
        with os.fdopen(descriptor, "w", encoding="utf-8") as output_handle:
            output_handle.write("\n".join(lines))
            output_handle.write("\n")
            output_handle.flush()
            os.fsync(output_handle.fileno())
        os.replace(temporary_path, path)
    except Exception:
        temporary_path.unlink(missing_ok=True)
        raise


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(add_help=False)
    parser.add_argument("--family", choices=("ipv4", "ipv6"), required=True)
    parser.add_argument("--subnet", required=True)
    parser.add_argument("--pool", required=True)
    parser.add_argument("--source", type=Path)
    parser.add_argument("--template", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--lease-directory", type=Path, required=True)
    parser.add_argument("--dns-output", type=Path)
    parser.add_argument("--dns-namespace")
    parser.add_argument(
        "--dns-record-class", action="append", choices=tuple(sorted(DNS_RECORD_CLASSES))
    )
    parser.add_argument("--dns-group")
    return parser.parse_args()


def main() -> None:
    args = parse_args()
    dns_options = [args.dns_output, args.dns_namespace, args.dns_group]
    dns_enabled = any(value is not None for value in dns_options) or bool(
        args.dns_record_class
    )
    require(
        not dns_enabled
        or (
            args.source is not None
            and all(value is not None for value in dns_options)
            and bool(args.dns_record_class)
        )
    )
    args.lease_directory.mkdir(parents=True, exist_ok=True, mode=0o700)
    with args.template.open("r", encoding="utf-8") as template_handle:
        config = json.load(template_handle)

    joined: list[dict[str, Any]] = []
    if args.source is not None:
        config, joined = insert_reservations(
            config, args.family, args.source, False
        )

    if dns_enabled:
        dns_lines, _ = materialize_dns_lines(
            args.dns_namespace,
            args.dns_record_class,
            args.family,
            joined,
        )
        atomic_write_dns(args.dns_output, dns_lines, args.dns_group)

    atomic_write(args.output, config)


if __name__ == "__main__":
    try:
        main()
    except ReservationContractError as exc:
        msg = exc.args[0] if exc.args else DIAGNOSTIC
        print(
            f"{msg}: protected reservation set or Kea template rejected",
            file=sys.stderr,
        )
        raise SystemExit(1)
    except Exception:
        print(
            f"{DIAGNOSTIC}: protected reservation set or Kea template rejected",
            file=sys.stderr,
        )
        raise SystemExit(1)
