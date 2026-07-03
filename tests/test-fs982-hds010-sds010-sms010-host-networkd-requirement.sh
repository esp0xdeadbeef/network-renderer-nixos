#!/usr/bin/env bash
# GAMP-ID: FS-982-HDS-010-SDS-010-SMS-010-CMC-001
# GAMP-SCOPE: software-module-test
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${repo_root}/tests/lib/test-common.sh"

result_json="$(mktemp)"
stderr_file="$(mktemp)"
trap 'rm -f "${result_json}" "${stderr_file}"' EXIT

nix_eval_json_or_fail \
  "FS-982 host networkd requirement decision matrix" \
  "${result_json}" \
  "${stderr_file}" \
  env REPO_ROOT="${repo_root}" \
    nix eval \
      --extra-experimental-features 'nix-command flakes' \
      --impure --json --expr '
        let
          repoRoot = builtins.getEnv "REPO_ROOT";
          requiresNetworkd = import (repoRoot + "/s88/ControlModule/render/host-networkd-requirement.nix") { };

          case = args: requiresNetworkd ({
            renderedNetdevs = { };
            renderedNetworks = { };
            renderedContainers = { };
            mgmtManageDhcp = false;
          } // args);

          checks = {
            no_renderer_owned_network_surface_does_not_claim_networkd =
              case { } == false;

            management_dhcp_surface_requires_networkd =
              case { mgmtManageDhcp = true; } == true;

            explicit_host_netdev_requires_networkd =
              case { renderedNetdevs."10-br-lan-trunk".netdevConfig.Name = "br-lan-trunk"; } == true;

            explicit_host_network_requires_networkd =
              case { renderedNetworks."30-br-lan-trunk".matchConfig.Name = "br-lan-trunk"; } == true;

            primary_container_host_bridge_requires_networkd =
              case {
                renderedContainers.core = {
                  hostBridge = "br-wan6";
                  extraVeths = { };
                };
              } == true;

            extra_veth_host_bridge_requires_networkd =
              case {
                renderedContainers.core = {
                  extraVeths.wan.hostBridge = "br-wan6";
                };
              } == true;

            empty_primary_host_bridge_is_not_a_rendered_surface =
              case { renderedContainers.core.hostBridge = ""; } == false;

            empty_extra_veth_host_bridge_is_not_a_rendered_surface =
              case { renderedContainers.core.extraVeths.wan.hostBridge = ""; } == false;

            malformed_container_records_are_ignored =
              case {
                renderedContainers = {
                  core = "not-a-container";
                  policy.extraVeths.wan = "not-a-veth";
                };
              } == false;
          };
        in
        {
          ok = builtins.all (name: checks.${name}) (builtins.attrNames checks);
          failed = builtins.filter (name: !(checks.${name})) (builtins.attrNames checks);
          inherit checks;
        }
      '

assert_json_checks_ok "FS-982 host networkd requirement decision matrix" "${result_json}"

echo "PASS FS-982-HDS-010-SDS-010-SMS-010 host networkd requirement decision matrix"
