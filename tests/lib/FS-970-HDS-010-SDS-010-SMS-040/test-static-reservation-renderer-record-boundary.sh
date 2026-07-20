#!/usr/bin/env bash
# GAMP-ID: FS-970-HDS-010-SDS-010-SMS-040
# GAMP-SCOPE: software-module-test
set -euo pipefail

repo_root="${SMS_TEST_REPO_ROOT:-$(git -C "$(dirname "${BASH_SOURCE[0]}")" rev-parse --show-toplevel)}"
source "${repo_root}/tests/lib/test-common.sh"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

nix_eval_true_or_fail \
  static-reservation-renderer-record-boundary \
  env REPO_ROOT="${repo_root}" \
    nix eval \
    --extra-experimental-features 'nix-command flakes' \
    --impure --expr '
      let
        repoRoot = builtins.getEnv "REPO_ROOT";
        flake = builtins.getFlake ("path:" + repoRoot);
        lib = flake.inputs.nixpkgs.lib;
        model =
          import (repoRoot + "/s88/ControlModule/access/lookup/advertisements.nix") {
            inherit lib;
            containerModel = {
              interfaces.tenant-client = {
                interfaceName = "tenant-client";
                sourceKind = "tenant";
                addresses = [ "10.20.20.1/24" "fd42:dead:beef:20::1/64" ];
              };
              runtimeTarget = {
                advertisements = {
                  dhcp4 = [
                    {
                      id = "client-v4";
                      enabled = true;
                      interface = "tenant-client";
                      tenant = "client";
                      subnet = "10.20.20.0/24";
                      pool = "10.20.20.100 - 10.20.20.199";
                      router = "10.20.20.1";
                      dnsServers = [ "10.20.20.1" ];
                      domain = "lan.";
                      reservations = [
                        {
                          id = "client-fixed-10";
                          hostname = "client-fixed-10";
                          mac = "02:10:20:00:00:10";
                          hostOffset = 10;
                          address = "10.20.20.10";
                          cidr = "10.20.20.10/32";
                          source = "inventory-realization";
                        }
                      ];
                    }
                  ];
                  dhcpv6 = [
                    {
                      id = "client-v6";
                      enabled = true;
                      interface = "tenant-client";
                      tenant = "client";
                      subnet = "fd42:dead:beef:20::/64";
                      pool = "fd42:dead:beef:20::100 - fd42:dead:beef:20::1ff";
                      dnsServers = [ "fd42:dead:beef:20::1" ];
                      domain = "lan.";
                      reservations = [
                        {
                          id = "client-fixed-v6-10";
                          hostname = "client-fixed-v6-10";
                          mac = "02:10:20:00:00:10";
                          hostOffset = 16;
                          address = "fd42:dead:beef:20:0:0:0:10";
                          cidr = "fd42:dead:beef:20:0:0:0:10/128";
                          source = "inventory-realization";
                        }
                      ];
                    }
                  ];
                };
                stateContracts.persistence.dhcp4Leases = [
                  {
                    service = "dhcp4";
                    id = "client-v4";
                    kind = "lease-state";
                    mode = "ephemeral";
                    required = false;
                    interface = "tenant-client";
                    tenant = "client";
                    source = "inventory-realization";
                    runtimeLocation = "ephemeral";
                  }
                ];
                stateContracts.persistence.dhcpv6Leases = [
                  {
                    service = "dhcpv6";
                    id = "client-v6";
                    kind = "lease-state";
                    mode = "ephemeral";
                    required = false;
                    interface = "tenant-client";
                    tenant = "client";
                    source = "inventory-realization";
                    runtimeLocation = "ephemeral";
                  }
                ];
              };
            };
          };
        scope4 = builtins.head model.dhcp4Scopes;
        scope6 = builtins.head model.dhcpv6Scopes;
        reservation4 = builtins.head scope4.reservations;
        reservation6 = builtins.head scope6.reservations;
      in
        model.radvdScopes == [ ]
        && builtins.length model.dhcp4Scopes == 1
        && builtins.length model.dhcpv6Scopes == 1
        && scope4.subnet == "10.20.20.0/24"
        && scope6.subnet == "fd42:dead:beef:20::/64"
        && reservation4.mac == "02:10:20:00:00:10"
        && reservation4.address == "10.20.20.10"
        && reservation4.cidr == "10.20.20.10/32"
        && reservation4.source == "inventory-realization"
        && reservation6.mac == "02:10:20:00:00:10"
        && reservation6.address == "fd42:dead:beef:20:0:0:0:10"
        && reservation6.cidr == "fd42:dead:beef:20:0:0:0:10/128"
        && reservation6.source == "inventory-realization"
    '

assert_rejects() {
  local label="$1"
  local expected="$2"
  local expr="$3"

  if env REPO_ROOT="${repo_root}" nix eval \
    --extra-experimental-features 'nix-command flakes' \
    --impure --expr "$expr" >"${tmp}/${label}.out" 2>"${tmp}/${label}.err"; then
    cat "${tmp}/${label}.out" >&2
    fail "FAIL static-reservation-renderer-record-boundary: ${label} was accepted"
  fi

  grep -F "$expected" "${tmp}/${label}.err" >/dev/null || {
    cat "${tmp}/${label}.err" >&2
    fail "FAIL static-reservation-renderer-record-boundary: ${label} diagnostic did not contain: ${expected}"
  }
}

nix_expr_for() {
  local dhcp4_entry="$1"
  cat <<EOF
let
  repoRoot = builtins.getEnv "REPO_ROOT";
  flake = builtins.getFlake ("path:" + repoRoot);
  lib = flake.inputs.nixpkgs.lib;
  model =
    import (repoRoot + "/s88/ControlModule/access/lookup/advertisements.nix") {
      inherit lib;
      containerModel = {
        interfaces.tenant-client = {
          interfaceName = "tenant-client";
          sourceKind = "tenant";
          addresses = [ "10.20.20.1/24" ];
        };
        runtimeTarget.advertisements.dhcp4 = [ ${dhcp4_entry} ];
      };
    };
in
  builtins.deepSeq model true
EOF
}

assert_rejects \
  reservations-not-list \
  "runtimeTarget.advertisements.dhcp4[0].reservations must be a list" \
  "$(nix_expr_for '{ id = "client"; enabled = true; interface = "tenant-client"; subnet = "10.20.20.0/24"; pool = "10.20.20.100 - 10.20.20.199"; router = "10.20.20.1"; reservations = { mac = "02:10:20:00:00:10"; address = "10.20.20.10"; }; }')"

assert_rejects \
  missing-resolved-address \
  "runtimeTarget.advertisements.dhcp4[0].reservations[0].address must be a non-empty string" \
  "$(nix_expr_for '{ id = "client"; enabled = true; interface = "tenant-client"; subnet = "10.20.20.0/24"; pool = "10.20.20.100 - 10.20.20.199"; router = "10.20.20.1"; reservations = [ { mac = "02:10:20:00:00:10"; } ]; }')"

assert_rejects \
  missing-served-scope \
  "runtimeTarget.advertisements.dhcp4[0].subnet must be a non-empty string" \
  "$(nix_expr_for '{ id = "client"; enabled = true; interface = "tenant-client"; pool = "10.20.20.100 - 10.20.20.199"; router = "10.20.20.1"; reservations = [ { mac = "02:10:20:00:00:10"; address = "10.20.20.10"; } ]; }')"

assert_rejects \
  unrelated-network-authority \
  "must not carry unrelated network authority fields: routes, dnsRecursion, publicEgress" \
  "$(nix_expr_for '{ id = "client"; enabled = true; interface = "tenant-client"; subnet = "10.20.20.0/24"; pool = "10.20.20.100 - 10.20.20.199"; router = "10.20.20.1"; reservations = [ { mac = "02:10:20:00:00:10"; address = "10.20.20.10"; dnsRecursion = true; publicEgress = true; routes = [ "0.0.0.0/0" ]; } ]; }')"

echo "PASS static-reservation-renderer-record-boundary"
