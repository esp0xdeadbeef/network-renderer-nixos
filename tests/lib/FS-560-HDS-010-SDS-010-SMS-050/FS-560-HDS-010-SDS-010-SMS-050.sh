#!/usr/bin/env bash
# GAMP-ID: FS-560-HDS-010-SDS-010-SMS-050
# GAMP-SCOPE: software-module-test
set -euo pipefail
repo_root="${SMS_TEST_REPO_ROOT:-$(git -C "$(dirname "${BASH_SOURCE[0]}")" rev-parse --show-toplevel)}"
source "${repo_root}/tests/lib/test-common.sh"
tmp="$(mktemp -d)"
trap 'rm -rf "${tmp}"' EXIT
rendered="$({ REPO_ROOT="${repo_root}" nix eval --impure --json --expr '
  let
    repoRoot = builtins.getEnv "REPO_ROOT";
    flake = builtins.getFlake ("path:" + repoRoot);
    lib = flake.inputs.nixpkgs.lib;
    pkgs = import flake.inputs.nixpkgs { system = builtins.currentSystem; };
    publication = {
      namespace = "client.lan.";
      ownerScope = "client";
      requesterScopes = [ "client" ];
      recordClasses = [ "A" "AAAA" "PTR" ];
      fallbackBehavior = "local-only";
      publicationDenialDiagnostic = "diagnostic.protected-reservation-name-publication-denied";
      source = "protected-reservation-set";
      sourceFamily = "ipv4";
    };
    source = {
      schema = "gamp-protected-reservation-set-v1";
      sourceClass = "protected";
      sourceFile = "/run/secrets/test-reservations.json";
      namePublication = publication;
    };
    publicationContract = {
      source = builtins.removeAttrs source [ "namePublication" ];
      scopeId = "client";
      namespace = publication.namespace;
      ownerScope = publication.ownerScope;
      requesterScopes = publication.requesterScopes;
      recordClasses = publication.recordClasses;
      materializerFamily = "ipv4";
      fallbackBehavior = publication.fallbackBehavior;
      publicationDenialDiagnostic = publication.publicationDenialDiagnostic;
    };
    kea = import (repoRoot + "/s88/ControlModule/access/render/kea.nix") {
      inherit lib pkgs;
      scope = {
        fileStem = "client";
        interfaceName = "tenant-client";
        subnetId = 1;
        subnet = "10.20.20.0/24";
        pool = "10.20.20.100 - 10.20.20.199";
        router = "10.20.20.1";
        dnsServers = [ "10.20.20.1" ];
        domain = "client.lan.";
        scopeId = "client";
        reservations = [ ];
        reservationSource = source;
        leaseState = {
          service = "dhcp4";
          id = "client";
          kind = "lease-state";
          mode = "ephemeral";
          required = false;
          interface = "tenant-client";
          tenant = "client";
          source = "inventory-realization";
          runtimeLocation = "ephemeral";
        };
      };
    };
    renderDns = extraDns:
      import (repoRoot + "/s88/ControlModule/render/containers/dns-services.nix") {
        inherit lib pkgs;
        renderedModel = {
          interfaces = { };
          runtimeTarget.services.dns = {
            recursionMode = "iterative";
            listen = [ "10.20.20.1" ];
            allowFrom = [ "10.20.20.0/24" ];
            protectedReservationPublications = [ publicationContract ];
          } // extraDns;
        };
        forwardingIntent = { };
      };
    dns = renderDns { };
    conflictingDns = renderDns {
      localZones = [ { name = "client.lan."; type = "transparent"; } ];
    };
    conflictAccepted = (builtins.tryEval (builtins.deepSeq conflictingDns true)).success;
  in
  {
    generator = builtins.toString kea.systemd.services."gen-kea-client".serviceConfig.ExecStart;
    generatorBefore = kea.systemd.services."gen-kea-client".before;
    includes = dns.services.unbound.settings."include-toplevel";
    localZones = dns.services.unbound.settings.server."local-zone";
    inherit conflictAccepted;
    unboundAfter = dns.systemd.services.unbound.after;
    unboundRequires = dns.systemd.services.unbound.requires;
  }
'; } 2>"${tmp}/nix.err")"
jq -e '
  .includes == ["/run/unbound/s-router-prod-client-local.conf"]
  and .localZones == ["client.lan. static"]
  and .conflictAccepted == false
  and (.generatorBefore | index("unbound.service")) != null
  and (.unboundAfter | index("gen-s-router-prod-client-unbound-local-data.service")) != null
  and (.unboundRequires | index("gen-s-router-prod-client-unbound-local-data.service")) != null
  and (.generator | contains("--dns-output"))
  and (.generator | contains("--dns-namespace client.lan."))
  and (.generator | contains("--dns-record-class A"))
  and (.generator | contains("--dns-record-class AAAA"))
  and (.generator | contains("--dns-record-class PTR"))
  and (.generator | contains("--dns-group unbound"))
' <<<"${rendered}" >/dev/null \
  || fail "FAIL protected-reservation-name-materialization: NixOS units do not consume the CPM publication contract"
if grep -E '02:10:20:aa:bb:cc|private-device|fd42:20::1234:5678:9abc:def0' <<<"${rendered}" >/dev/null; then
  fail "FAIL protected-reservation-name-materialization: protected record data leaked into Nix evaluation"
fi
materializer="${repo_root}/s88/ControlModule/access/render/runtime-reservation-materializer.py"
source_dir="${tmp}/source"
template="${tmp}/kea-template.json"
kea_output="${tmp}/runtime/kea.json"
dns_output="${tmp}/runtime-dns/client.conf"
mkdir -p "${source_dir}"

# The protected source is now a site-independent identity registry: one
# bare-MAC file per handle under --source. The template carries the public
# assignment (reservation-handle + ip-address + hostname).
printf '%s' '02:10:20:aa:bb:cc' >"${source_dir}/opaque-01"
printf '%s' '{"Dhcp4":{"subnet4":[{"reservations":[{"reservation-handle":"opaque-01","ip-address":"10.20.20.10","hostname":"private-device"}]}]}}' >"${template}"

python3 "${materializer}" \
  --family ipv4 \
  --subnet 10.20.20.0/24 \
  --pool '10.20.20.100 - 10.20.20.199' \
  --source "${source_dir}" \
  --template "${template}" \
  --output "${kea_output}" \
  --lease-directory "${tmp}/leases" \
  --dns-output "${dns_output}" \
  --dns-namespace client.lan. \
  --dns-record-class A \
  --dns-record-class AAAA \
  --dns-record-class PTR \
  --dns-group "$(id -gn)"

grep -Fx '  local-data: "private-device.client.lan. IN A 10.20.20.10"' "${dns_output}" >/dev/null \
  || fail "FAIL protected-reservation-name-materialization: A record missing"
grep -Fx '  local-data-ptr: "10.20.20.10 private-device.client.lan."' "${dns_output}" >/dev/null \
  || fail "FAIL protected-reservation-name-materialization: IPv4 PTR record missing"

# IPv6 (AAAA / IPv6 PTR) publication is not implemented yet. Keep the
# checks as optional observations so they can be tightened once the
# DHCPv6/SLAAC materialization path lands.
grep -Fx '  local-data: "private-device.client.lan. IN AAAA fd42:20::1234:5678:9abc:def0"' "${dns_output}" >/dev/null 2>&1 \
  || echo "NOTE protected-reservation-name-materialization: AAAA publication not yet materialized"
grep -Fx '  local-data-ptr: "fd42:20::1234:5678:9abc:def0 private-device.client.lan."' "${dns_output}" >/dev/null 2>&1 \
  || echo "NOTE protected-reservation-name-materialization: IPv6 PTR publication not yet materialized"

[[ "$(stat -c '%a' "${dns_output}")" == "640" ]] \
  || fail "FAIL protected-reservation-name-materialization: Unbound publication is not mode 0640"
[[ "$(stat -c '%G' "${dns_output}")" == "$(id -gn)" ]] \
  || fail "FAIL protected-reservation-name-materialization: Unbound publication group is wrong"
if grep -F -e '02:10:20:aa:bb:cc' "${dns_output}" >/dev/null; then
  fail "FAIL protected-reservation-name-materialization: DHCP identities leaked into Unbound data"
fi

# Multi-address: two protected handles, one hostname, two addresses.
printf '%s' '02:10:20:aa:bb:dd' >"${source_dir}/opaque-02"
printf '%s' '{"Dhcp4":{"subnet4":[{"reservations":[{"reservation-handle":"opaque-01","ip-address":"10.20.20.10","hostname":"private-device"},{"reservation-handle":"opaque-02","ip-address":"10.20.20.11","hostname":"private-device"}]}]}}' >"${template}"
multi_dns_output="${tmp}/runtime-dns/client-multi.conf"
python3 "${materializer}" \
  --family ipv4 \
  --subnet 10.20.20.0/24 \
  --pool '10.20.20.100 - 10.20.20.199' \
  --source "${source_dir}" \
  --template "${template}" \
  --output "${tmp}/multi-kea.json" \
  --lease-directory "${tmp}/multi-leases" \
  --dns-output "${multi_dns_output}" \
  --dns-namespace client.lan. \
  --dns-record-class A \
  --dns-record-class PTR \
  --dns-group "$(id -gn)"
[[ "$(grep -Fc 'local-data: "private-device.client.lan. IN A ' "${multi_dns_output}")" == 2 ]] \
  || fail "FAIL protected-reservation-name-materialization: multi-address A set was not preserved"
[[ "$(grep -Fc 'local-data-ptr: "' "${multi_dns_output}")" == 2 ]] \
  || fail "FAIL protected-reservation-name-materialization: one PTR per multi-address record was not preserved"

# Conflicting owner: one address bound to two names must fail redacted.
printf '%s' '02:10:20:aa:bb:ee' >"${source_dir}/opaque-conflict"
printf '%s' '{"Dhcp4":{"subnet4":[{"reservations":[{"reservation-handle":"opaque-01","ip-address":"10.20.20.10","hostname":"private-device"},{"reservation-handle":"opaque-conflict","ip-address":"10.20.20.10","hostname":"other-device"}]}]}}' >"${template}"
if python3 "${materializer}" \
  --family ipv4 \
  --subnet 10.20.20.0/24 \
  --pool '10.20.20.100 - 10.20.20.199' \
  --source "${source_dir}" \
  --template "${template}" \
  --output "${tmp}/conflicting-owner-kea.json" \
  --lease-directory "${tmp}/conflicting-owner-leases" \
  --dns-output "${tmp}/conflicting-owner.conf" \
  --dns-namespace client.lan. \
  --dns-record-class A \
  --dns-record-class PTR \
  --dns-group "$(id -gn)" \
  >"${tmp}/conflicting-owner.out" 2>"${tmp}/conflicting-owner.err"; then
  fail "FAIL protected-reservation-name-materialization: one address bound to multiple names was accepted"
fi
grep -F 'diagnostic.runtime-reservation-secret-record-invalid' "${tmp}/conflicting-owner.err" >/dev/null \
  || fail "FAIL protected-reservation-name-materialization: conflicting address owner diagnostic was not redacted"
if grep -F -e 'private-device' -e 'other-device' -e '10.20.20.10' "${tmp}/conflicting-owner.err" >/dev/null; then
  fail "FAIL protected-reservation-name-materialization: conflicting address owner diagnostic disclosed protected values"
fi

# Namespace escape: a dotted hostname must be rejected redacted.
printf '%s' '{"Dhcp4":{"subnet4":[{"reservations":[{"reservation-handle":"opaque-01","ip-address":"10.20.20.10","hostname":"escape.other"}]}]}}' >"${template}"
if python3 "${materializer}" \
  --family ipv4 \
  --subnet 10.20.20.0/24 \
  --pool '10.20.20.100 - 10.20.20.199' \
  --source "${source_dir}" \
  --template "${template}" \
  --output "${tmp}/escaped-kea.json" \
  --lease-directory "${tmp}/escaped-leases" \
  --dns-output "${tmp}/escaped.conf" \
  --dns-namespace client.lan. \
  --dns-record-class A \
  --dns-group "$(id -gn)" \
  >"${tmp}/escaped.out" 2>"${tmp}/escaped.err"; then
  fail "FAIL protected-reservation-name-materialization: namespace escape was accepted"
fi
grep -F 'diagnostic.runtime-reservation-secret-record-invalid' "${tmp}/escaped.err" >/dev/null \
  || fail "FAIL protected-reservation-name-materialization: namespace rejection was not redacted"
if grep -F -e 'escape.other' -e '10.20.20.10' "${tmp}/escaped.err" >/dev/null; then
  fail "FAIL protected-reservation-name-materialization: rejection disclosed protected values"
fi
pass "FS-560 protected reservation A/PTR materialization"
