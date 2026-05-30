#!/usr/bin/env bash
# GAMP-ID: USR-MODEL-001-FS-001-HDS-002-SDS-001-001-SMS-001-016
# GAMP-ID: USR-MODEL-001-FS-001-HDS-002-SDS-001-001-SMS-001-CMC-001-016
# GAMP-SCOPE: software-module-test
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${repo_root}/tests/lib/test-common.sh"

result_json="$(mktemp)"
eval_stderr="$(mktemp)"
trap 'rm -f "${result_json}" "${eval_stderr}"' EXIT

nix_eval_json_or_fail \
  static-client-address-render \
  "${result_json}" \
  "${eval_stderr}" \
  env REPO_ROOT="${repo_root}" \
    nix eval \
    --extra-experimental-features 'nix-command flakes' \
    --impure --json --expr '
      let
        repoRoot = builtins.getEnv "REPO_ROOT";
        flake = builtins.getFlake ("path:" + repoRoot);
        lib = flake.inputs.nixpkgs.lib;
        render = interfaces:
          import (repoRoot + "/s88/ControlModule/render/container-networks.nix") {
            inherit lib;
            uplinks = { };
            wanUplinkName = null;
            containerModel = { inherit interfaces; };
          };
        withStatic = render {
          tenant-client = {
            containerInterfaceName = "tenant-client";
            sourceKind = "tenant";
            backingRef = {
              kind = "attachment";
              name = "client";
            };
            addresses = [ "10.20.20.1/24" "fd42:dead:beef:20::1/64" ];
            routes = [ ];
          };
        };
        withoutStatic = render {
          tenant-client = {
            containerInterfaceName = "tenant-client";
            sourceKind = "tenant";
            backingRef = {
              kind = "attachment";
              name = "client";
            };
            routes = [ ];
          };
        };
        staticNetwork = withStatic.networks."10-tenant-client" or { };
        absentNetwork = withoutStatic.networks."10-tenant-client" or { };
        checks = {
          static_network_unit_exists = withStatic.networks ? "10-tenant-client";
          static_addresses_projected =
            (staticNetwork.address or [ ]) == [ "10.20.20.1/24" "fd42:dead:beef:20::1/64" ];
          absent_contract_projects_no_static_addresses = (absentNetwork.address or [ ]) == [ ];
          no_dynamic_dhcp_in_static_fixture = !((staticNetwork.networkConfig or { }) ? DHCP);
        };
      in
      {
        ok = builtins.all (name: checks.${name}) (builtins.attrNames checks);
        failed = builtins.filter (name: !(checks.${name})) (builtins.attrNames checks);
        inherit checks staticNetwork absentNetwork;
      }
    '

assert_json_checks_ok static-client-address-render "${result_json}"

echo "PASS static-client-address-render"
