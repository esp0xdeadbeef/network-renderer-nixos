#!/usr/bin/env bash
set -euo pipefail
# GAMP-ID: FS-270-HDS-010-SDS-010-SMS-020
# GAMP-SCOPE: software-module-test
#
# Every realized egress chain must be able to leave the site:
#
#   core -> upstream-selector -> policy -> downstream-selector -> access -> client
#
# The 2026-11-10 outage proved that a host can render "successfully" while the
# provider VLAN interface is never created: `11-eth1.300.netdev` existed but
# networkd produced no `eth1.300` link at all, so DWCP discovered with no offer
# (`udhcpc: no lease, failing`), `wan` stayed link-local, and there was no
# default route. The same hardware egressed instantly in OpenWrt with the
# documented `config device type 8021q` + `proto dhcp`, so the defect is in the
# render, not the L2.
#
# This test asserts the render-side preconditions for egress:
#   P1 the WAN-side VLAN exists as a netdev AND names its parent trunk port
#      (a VLAN netdev without a parent is what networkd silently ignores)
#   P2 every hop of the chain has at least one container interface that is
#      attached to a host bridge (an unattached veth removes the path while
#      every unit still reports healthy)
#
# It deliberately does not claim runtime egress; that needs the VM test.

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${repo_root}/tests/lib/test-common.sh"

example_root="${repo_root}/tests/fixtures/s-router-overlay-dns-lane-policy"

nix_eval_true_or_fail "egress-chain P1 WAN VLAN netdev names its parent" \
  env REPO_ROOT="${repo_root}" \
      INTENT_PATH="${example_root}/intent.nix" \
      INVENTORY_PATH="${example_root}/inventory-nixos.nix" \
  nix eval --extra-experimental-features 'nix-command flakes' --impure --expr '
    let
      lib = (builtins.getFlake ("path:" + builtins.getEnv "REPO_ROOT")).inputs.nixpkgs.lib;
      host = import (builtins.getEnv "REPO_ROOT" + "/tests/nix/build-host-from-paths.nix") {
        selector = "s-router-test";
        system = "x86_64-linux";
        intentPath = builtins.getEnv "INTENT_PATH";
        inventoryPath = builtins.getEnv "INVENTORY_PATH";
      };
      netdevs = host.renderedHost.netdevs or { };
      vlans = builtins.filter
        (n:
          ((netdevs.${n}.netdevConfig or { }).Kind or null) == "vlan")
        (builtins.attrNames netdevs);
      hasParent = n:
        let
          vlan = netdevs.${n}.vlanConfig or netdevs.${n}.netdevConfig or { };
        in
        (vlan.Parent or "") != "";
    in
      builtins.length vlans > 0 && builtins.all hasParent vlans
  '

nix_eval_true_or_fail "egress-chain P2 every hop is attached to a host bridge" \
  env REPO_ROOT="${repo_root}" \
      INTENT_PATH="${example_root}/intent.nix" \
      INVENTORY_PATH="${example_root}/inventory-nixos.nix" \
  nix eval --extra-experimental-features 'nix-command flakes' --impure --expr '
    let
      host = import (builtins.getEnv "REPO_ROOT" + "/tests/nix/build-host-from-paths.nix") {
        selector = "s-router-test";
        system = "x86_64-linux";
        intentPath = builtins.getEnv "INTENT_PATH";
        inventoryPath = builtins.getEnv "INVENTORY_PATH";
      };
      containers = host.renderedHost.containers or { };
      names = builtins.attrNames containers;
      attached = name:
        let
          c = containers.${name};
          veths = c.extraVeths or { };
        in
        (c.hostBridge or null) != null
        || builtins.any
             (v: (v.hostBridge or null) != null)
             (builtins.attrValues veths);
    in
      builtins.length names > 0 && builtins.all attached names
  '

pass "egress-chain VLAN + host-bridge preconditions"
