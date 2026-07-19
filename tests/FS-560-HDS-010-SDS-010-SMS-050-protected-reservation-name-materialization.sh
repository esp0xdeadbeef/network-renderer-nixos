#!/usr/bin/env bash
# GAMP-ID: FS-560-HDS-010-SDS-010-SMS-050
# GAMP-SCOPE: software-module-test
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
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
    dns = import (repoRoot + "/s88/ControlModule/render/containers/dns-services.nix") {
      inherit lib pkgs;
      renderedModel = {
        interfaces = { };
        runtimeTarget.services.dns = {
          recursionMode = "iterative";
          listen = [ "10.20.20.1" ];
          allowFrom = [ "10.20.20.0/24" ];
          protectedReservationPublications = [
            {
              source = builtins.removeAttrs source [ "namePublication" ];
              scopeId = "client";
              namespace = publication.namespace;
              ownerScope = publication.ownerScope;
              requesterScopes = publication.requesterScopes;
              recordClasses = publication.recordClasses;
              materializerFamily = "ipv4";
              fallbackBehavior = publication.fallbackBehavior;
              publicationDenialDiagnostic = publication.publicationDenialDiagnostic;
            }
          ];
        };
      };
      forwardingIntent = { };
    };
  in
  {
    generator = builtins.toString kea.systemd.services."gen-kea-client".serviceConfig.ExecStart;
    generatorBefore = kea.systemd.services."gen-kea-client".before;
    includes = dns.services.unbound.settings.server.include;
    unboundAfter = dns.systemd.services.unbound.after;
    unboundRequires = dns.systemd.services.unbound.requires;
  }
'; } 2>"${tmp}/nix.err")"

jq -e '
  .includes == ["/run/protected-reservation-dns/client.conf"]
  and (.generatorBefore | index("unbound.service")) != null
  and (.unboundAfter | index("gen-kea-client.service")) != null
  and (.unboundRequires | index("gen-kea-client.service")) != null
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
template="${tmp}/kea-template.json"
secret="${tmp}/protected.json"
kea_output="${tmp}/runtime/kea.json"
dns_output="${tmp}/runtime-dns/client.conf"

printf '%s\n' '{"Dhcp4":{"subnet4":[{"reservations":[]}]}}' >"${template}"
printf '%s\n' '[{"id":"opaque-01","scope":"client","hostname":"private-device","ipv4":{"address":"10.20.20.10","mac-address":"02:10:20:aa:bb:cc"},"ipv6":{"address":"fd42:20::1234:5678:9abc:def0","iid":"123456789abcdef0","iid-stability":"stable","duid":"0001000123456789001122334455","iaid":7}}]' >"${secret}"

python3 "${materializer}" \
  --family ipv4 \
  --scope client \
  --subnet 10.20.20.0/24 \
  --pool '10.20.20.100 - 10.20.20.199' \
  --source "${secret}" \
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
grep -Fx '  local-data: "private-device.client.lan. IN AAAA fd42:20::1234:5678:9abc:def0"' "${dns_output}" >/dev/null \
  || fail "FAIL protected-reservation-name-materialization: AAAA record missing"
grep -Fx '  local-data-ptr: "10.20.20.10 private-device.client.lan."' "${dns_output}" >/dev/null \
  || fail "FAIL protected-reservation-name-materialization: IPv4 PTR record missing"
grep -Fx '  local-data-ptr: "fd42:20::1234:5678:9abc:def0 private-device.client.lan."' "${dns_output}" >/dev/null \
  || fail "FAIL protected-reservation-name-materialization: IPv6 PTR record missing"
[[ "$(stat -c '%a' "${dns_output}")" == "640" ]] \
  || fail "FAIL protected-reservation-name-materialization: Unbound publication is not mode 0640"
[[ "$(stat -c '%G' "${dns_output}")" == "$(id -gn)" ]] \
  || fail "FAIL protected-reservation-name-materialization: Unbound publication group is wrong"
if grep -F -e '02:10:20:aa:bb:cc' -e '0001000123456789001122334455' "${dns_output}" >/dev/null; then
  fail "FAIL protected-reservation-name-materialization: DHCP identities leaked into Unbound data"
fi

escaped_secret="${tmp}/escaped.json"
jq '.[0].hostname = "escape.other"' "${secret}" >"${escaped_secret}"
if python3 "${materializer}" \
  --family ipv4 --scope client --subnet 10.20.20.0/24 \
  --pool '10.20.20.100 - 10.20.20.199' \
  --source "${escaped_secret}" --template "${template}" \
  --output "${tmp}/escaped-kea.json" --lease-directory "${tmp}/escaped-leases" \
  --dns-output "${tmp}/escaped.conf" --dns-namespace client.lan. \
  --dns-record-class A --dns-group "$(id -gn)" \
  >"${tmp}/escaped.out" 2>"${tmp}/escaped.err"; then
  fail "FAIL protected-reservation-name-materialization: namespace escape was accepted"
fi
grep -F 'diagnostic.runtime-reservation-secret-record-invalid' "${tmp}/escaped.err" >/dev/null \
  || fail "FAIL protected-reservation-name-materialization: namespace rejection was not redacted"
if grep -F -e 'escape.other' -e '10.20.20.10' "${tmp}/escaped.err" >/dev/null; then
  fail "FAIL protected-reservation-name-materialization: rejection disclosed protected values"
fi

pass "FS-560 protected reservation A/AAAA/PTR materialization"
