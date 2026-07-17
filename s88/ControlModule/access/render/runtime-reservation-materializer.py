#!/usr/bin/env python3
"""Materialize one protected reservation set into a runtime-local Kea config."""

from __future__ import annotations

import argparse
import ipaddress
import json
import os
from pathlib import Path
import re
import sys
import tempfile
from typing import Any


DIAGNOSTIC = "diagnostic.runtime-reservation-secret-record-invalid"
SCHEMA_FIELDS = {"id", "scope", "ipv4", "ipv6", "hostname"}
HOSTNAME = re.compile(r"^[A-Za-z0-9][A-Za-z0-9._-]*$")
MAC = re.compile(r"^(?:[0-9A-Fa-f]{2}:){5}[0-9A-Fa-f]{2}$")
IID = re.compile(r"^[0-9A-Fa-f]{16}$")
DUID = re.compile(r"^[0-9A-Fa-f]{4,260}$")


class ReservationContractError(Exception):
    """A protected source failed the redacted runtime contract."""


def require(condition: bool) -> None:
    if not condition:
        raise ReservationContractError


def normalized_iid(value: object) -> int:
    require(isinstance(value, str))
    compact = value.replace(":", "").replace("-", "")
    require(IID.fullmatch(compact) is not None)
    return int(compact, 16)


def normalized_duid(value: object) -> str:
    require(isinstance(value, str))
    compact = value.replace(":", "").replace("-", "")
    require(len(compact) % 2 == 0 and DUID.fullmatch(compact) is not None)
    return compact.lower()


def materialize_records(
    family: str, scope: str, subnet_text: str, source_path: Path
) -> list[dict[str, Any]]:
    require(family in {"ipv4", "ipv6"})
    require(scope != "")
    network = ipaddress.ip_network(subnet_text, strict=True)
    require(
        (family == "ipv4" and network.version == 4)
        or (family == "ipv6" and network.version == 6)
    )

    with source_path.open("r", encoding="utf-8") as source_handle:
        source = json.load(source_handle)
    require(isinstance(source, list) and len(source) > 0)

    emitted: list[dict[str, Any]] = []
    ids: set[str] = set()
    identities: set[str] = set()
    addresses: set[str] = set()

    for record in source:
        require(isinstance(record, dict))
        require(set(record).issubset(SCHEMA_FIELDS))
        handle = record.get("id")
        require(isinstance(handle, str) and handle != "" and handle not in ids)
        ids.add(handle)
        require(record.get("scope") == scope)

        hostname = record.get("hostname")
        require(
            hostname is None
            or (isinstance(hostname, str) and HOSTNAME.fullmatch(hostname) is not None)
        )

        if family == "ipv4":
            identity = record.get("ipv4")
            require(isinstance(identity, dict))
            require(set(identity) == {"address", "mac-address"})
            address = ipaddress.IPv4Address(identity["address"])
            require(address in network)
            mac = identity["mac-address"]
            require(isinstance(mac, str) and MAC.fullmatch(mac) is not None)
            normalized_identity = mac.lower()
            emitted_record: dict[str, Any] = {
                "hw-address": normalized_identity,
                "ip-address": str(address),
            }
        else:
            identity = record.get("ipv6")
            require(isinstance(identity, dict))
            require(
                set(identity) == {"address", "iid", "iid-stability", "duid", "iaid"}
            )
            address = ipaddress.IPv6Address(identity["address"])
            require(address in network)
            iid = normalized_iid(identity["iid"])
            require(identity["iid-stability"] == "stable")
            require((int(address) & ((1 << 64) - 1)) == iid)
            normalized_identity = normalized_duid(identity["duid"])
            iaid = identity["iaid"]
            require(
                isinstance(iaid, int)
                and not isinstance(iaid, bool)
                and 0 <= iaid <= 0xFFFFFFFF
            )
            emitted_record = {
                "duid": normalized_identity,
                "ip-addresses": [str(address)],
            }

        normalized_address = str(address)
        require(
            normalized_identity not in identities
            and normalized_address not in addresses
        )
        identities.add(normalized_identity)
        addresses.add(normalized_address)
        if hostname is not None:
            emitted_record["hostname"] = hostname
        emitted.append(emitted_record)

    return emitted


def insert_reservations(
    config: dict[str, Any], family: str, runtime_records: list[dict[str, Any]]
) -> dict[str, Any]:
    if family == "ipv4":
        subnets = config["Dhcp4"]["subnet4"]
        identity_key = "hw-address"
    else:
        subnets = config["Dhcp6"]["subnet6"]
        identity_key = "duid"

    def reservation_address(record: dict[str, Any]) -> str:
        if family == "ipv4":
            return record["ip-address"]
        return record["ip-addresses"][0]

    require(isinstance(subnets, list) and len(subnets) == 1)
    existing = subnets[0].get("reservations", [])
    require(isinstance(existing, list))
    combined = existing + runtime_records
    require(
        len({record[identity_key] for record in combined}) == len(combined)
        and len({reservation_address(record) for record in combined}) == len(combined)
    )
    subnets[0]["reservations"] = combined
    return config


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


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(add_help=False)
    parser.add_argument("--family", choices=("ipv4", "ipv6"), required=True)
    parser.add_argument("--scope", required=True)
    parser.add_argument("--subnet", required=True)
    parser.add_argument("--source", type=Path)
    parser.add_argument("--template", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--lease-directory", type=Path, required=True)
    return parser.parse_args()


def main() -> None:
    args = parse_args()
    args.lease_directory.mkdir(parents=True, exist_ok=True, mode=0o700)
    with args.template.open("r", encoding="utf-8") as template_handle:
        config = json.load(template_handle)
    if args.source is not None:
        records = materialize_records(args.family, args.scope, args.subnet, args.source)
        config = insert_reservations(config, args.family, records)
    atomic_write(args.output, config)


if __name__ == "__main__":
    try:
        main()
    except Exception:
        print(
            f"{DIAGNOSTIC}: protected reservation set or Kea template rejected",
            file=sys.stderr,
        )
        raise SystemExit(1)
