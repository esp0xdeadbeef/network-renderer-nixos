#!/usr/bin/env bash
set -euo pipefail
# GAMP-ID: USR-MODEL-001-FS-001-HDS-002-SDS-001-001-SMS-001-005
# GAMP-ID: USR-MODEL-001-FS-001-HDS-002-SDS-001-001-SMS-001-CMC-001-005
# GAMP-SCOPE: software-module-test

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${repo_root}/tests/lib/test-common.sh"

result_json="$(mktemp)"
eval_stderr="$(mktemp)"
trap 'rm -f "${result_json}" "${eval_stderr}"' EXIT

nix_eval_json_or_fail \
  interface-mtu-render \
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
        render =
          import (repoRoot + "/s88/ControlModule/render/container-networks.nix") {
            inherit lib;
            uplinks = { };
            wanUplinkName = null;
            containerModel = {
              interfaces.client = {
                containerInterfaceName = "client0";
                sourceKind = "tenant";
                backingRef = {
                  kind = "attachment";
                  name = "client";
                };
                addresses = [ "10.20.20.1/24" "fd42:dead:beef:20::1/64" ];
                routes = [ ];
                mtu = 1492;
              };
            };
          };
        network = render.networks."10-client0" or { };
        checks = {
          network_unit_exists = render.networks ? "10-client0";
          mtu_projected = ((network.linkConfig or { }).MTUBytes or null) == 1492;
          name_preserved = ((network.matchConfig or { }).Name or null) == "client0";
        };
      in
      {
        ok = builtins.all (name: checks.${name}) (builtins.attrNames checks);
        failed = builtins.filter (name: !(checks.${name})) (builtins.attrNames checks);
        inherit checks network;
      }
    '

assert_json_checks_ok interface-mtu-render "${result_json}"

echo "PASS interface-mtu-render"
