#!/usr/bin/env bash
# GAMP-ID: FS-540-HDS-010-SDS-010-SMS-020
# GAMP-SCOPE: software-module-test
set -euo pipefail

repo_root="${SMS_TEST_REPO_ROOT:-$(git -C "$(dirname "${BASH_SOURCE[0]}")" rev-parse --show-toplevel)}"
source "${repo_root}/tests/lib/test-common.sh"

nix_eval_true_or_fail "FS-540 NixOS VLAN host uplink materialization" \
  env REPO_ROOT="${repo_root}" \
    nix eval \
      --extra-experimental-features 'nix-command flakes' \
      --impure --expr '
        let
          repoRoot = builtins.getEnv "REPO_ROOT";
          flake = builtins.getFlake ("path:" + repoRoot);
          lib = flake.inputs.nixpkgs.lib;
          helpers = import (repoRoot + "/s88/ControlModule/lookup/host-query/inventory/helpers.nix") { inherit lib; };
          source = {
            deploymentHosts.s-router-nixos.uplinks.testnet-vlan4 = {
              bridge = "testnet-vlan4";
              parent = "eth0";
              mode = "vlan";
              vlan = 4;
              ipv4.method = "dhcp";
              ipv6.method = "slaac";
            };
          };
          context = import (repoRoot + "/s88/Unit/lookup/host-runtime/context.nix") {
            inherit lib;
            hostName = "s-router-nixos";
            cpm = {
              control_plane_model.data = { };
              inherit (source) deploymentHosts;
            };
            source = { };
            hostContext = null;
          };
          selected = helpers.deploymentHostsFor source;
          hostPlan = {
            hostHasUplinks = true;
            deploymentHost = selected.s-router-nixos;
            bridges = { };
            bridgeNetworks = { };
            uplinks.testnet-vlan4 = selected.s-router-nixos.uplinks.testnet-vlan4 // {
              originalBridge = "testnet-vlan4";
              bridge = "rt--wan--test";
            };
            transitBridges = { };
          };
          rendered = import (repoRoot + "/s88/ControlModule/render/systemd-host-network.nix") {
            inherit lib hostPlan;
          };
          require = cond: msg: if cond then true else throw msg;
        in
          require (selected.s-router-nixos.uplinks.testnet-vlan4.mode == "vlan")
            "deploymentHostsFor must read top-level CPM deploymentHosts"
          && require (context.deploymentHost.uplinks.testnet-vlan4.vlan == 4)
            "host-runtime context must read top-level CPM deploymentHosts"
          && require (rendered.netdevs ? "11-eth0.4")
            "VLAN uplink must render eth0.4 netdev"
          && require (rendered.networks ? "21-eth0.4")
            "VLAN uplink must render eth0.4 bridge attachment"
          && require (rendered.networks."20-eth0".networkConfig.VLAN == [ "eth0.4" ])
            "parent eth0 must list VLAN child eth0.4"
      '

echo "PASS FS-540 NixOS VLAN host uplink materialization"
