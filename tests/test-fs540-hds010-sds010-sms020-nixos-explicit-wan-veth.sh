#!/usr/bin/env bash
# GAMP-ID: FS-540-HDS-010-SDS-010-SMS-020
# GAMP-SCOPE: software-module-test
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${repo_root}/tests/lib/test-common.sh"

result_json="$(mktemp)"
stderr_file="$(mktemp)"
trap 'rm -f "${result_json}" "${stderr_file}"' EXIT

nix_eval_json_or_fail \
  "FS-540 NixOS explicit WAN veth materialization" \
  "${result_json}" \
  "${stderr_file}" \
  env REPO_ROOT="${repo_root}" \
    nix eval \
      --extra-experimental-features 'nix-command flakes' \
      --impure --json --expr '
        let
          repoRoot = builtins.getEnv "REPO_ROOT";
          flake = builtins.getFlake ("path:" + repoRoot);
          lib = flake.inputs.nixpkgs.lib;
          lookup = {
            sortedAttrNames = attrs: builtins.sort builtins.lessThan (builtins.attrNames attrs);
            bridgeNameMap = { };
            localAttachTargets = [
              {
                unitName = "resolver-unit";
                ifName = "testnet-vlan4";
                renderedIfName = "u0";
                renderedHostBridgeName = "testnet-vlan4";
                assignedUplinkName = "testnet-vlan4";
                identity = {
                  attachmentKind = "synthetic";
                  portName = "testnet-vlan4";
                  unitName = "resolver-unit";
                };
              }
            ];
          };
          interfacesModule = import (repoRoot + "/s88/ControlModule/mapping/container-runtime/interfaces.nix") {
            inherit lib lookup;
          };
          normalized = interfacesModule.normalizedInterfacesForUnit {
            unitName = "resolver-unit";
            containerName = "resolver-node";
            interfaces = {
              testnet-vlan4 = {
                sourceKind = "wan";
                runtimeIfName = "u0";
                renderedIfName = "u0";
                hostBridge = "testnet-vlan4";
                connectivity = {
                  sourceKind = "wan";
                  upstream = "testnet-vlan4";
                };
                backingRef = {
                  kind = "link";
                  id = "uplink::mini-smt.dns-resolver-config::testnet-vlan4";
                  name = "testnet-vlan4";
                };
                ipv4 = {
                  enable = true;
                  method = "dhcp";
                  dhcp = true;
                };
                ipv6 = {
                  enable = true;
                  method = "slaac";
                  acceptRA = true;
                };
              };
            };
          };
          wan = normalized.testnet-vlan4;
          veths = interfacesModule.vethsForInterfaces normalized;
          hostVethName = wan.hostVethName or null;
          hostVeth =
            if hostVethName != null && builtins.hasAttr hostVethName veths then
              veths.${hostVethName}
            else
              { };
          checks = {
            runtime_ifname_preserved = wan.containerInterfaceName == "u0";
            primary_eth0_shortcut_not_used =
              (wan.usePrimaryHostBridge or false) == false
              && wan.containerInterfaceName != "eth0"
              && hostVethName != null;
            veth_attaches_to_modeled_bridge = (hostVeth.hostBridge or null) == "testnet-vlan4";
            assigned_uplink_preserved = (wan.assignedUplinkName or null) == "testnet-vlan4";
          };
        in
        {
          ok = builtins.all (name: checks.${name}) (builtins.attrNames checks);
          failed = builtins.filter (name: !(checks.${name})) (builtins.attrNames checks);
          inherit checks;
          observed = {
            inherit hostVethName veths;
            wan = {
              containerInterfaceName = wan.containerInterfaceName or null;
              hostInterfaceName = wan.hostInterfaceName or null;
              usePrimaryHostBridge = wan.usePrimaryHostBridge or null;
              assignedUplinkName = wan.assignedUplinkName or null;
            };
          };
        }
      '

assert_json_checks_ok "FS-540 NixOS explicit WAN veth materialization" "${result_json}"

echo "PASS FS-540 NixOS explicit WAN veth materialization"
