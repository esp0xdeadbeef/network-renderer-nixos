#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${repo_root}/tests/lib/test-common.sh"

example_root="$(flake_input_path network-labs)/examples/s-router-test-three-site"

REPO_ROOT="${repo_root}" \
INTENT_PATH="${example_root}/intent.nix" \
INVENTORY_PATH="${example_root}/inventory-nixos.nix" \
  nix eval \
    --extra-experimental-features 'nix-command flakes' \
    --impure --expr '
      let
        flake = builtins.getFlake ("path:" + builtins.getEnv "REPO_ROOT");
        host = flake.lib.renderer.buildHostFromPaths {
          selector = "s-router-test";
          system = "x86_64-linux";
          intentPath = builtins.getEnv "INTENT_PATH";
          inventoryPath = builtins.getEnv "INVENTORY_PATH";
        };
        uplinks = host.renderedHost.uplinks;
        networks = host.renderedHost.networks;
        uplinkNameForVlan = vlan:
          let
            matches = builtins.filter
              (name: (uplinks.${name}.vlan or null) == vlan)
              (builtins.attrNames uplinks);
          in
          if builtins.length matches == 1 then builtins.head matches else null;
        uplinkIsVlanDhcp = name:
          (uplinks.${name}.mode or null) == "vlan"
          && (uplinks.${name}.ipv4.dhcp or false)
          && (uplinks.${name}.ipv6.acceptRA or false);
        managementUplinkIsVlanDhcp = name:
          (uplinks.${name}.mode or null) == "vlan"
          && (uplinks.${name}.parent or null) == "eth0"
          && (uplinks.${name}.bridge or null) == "vlan2"
          && (uplinks.${name}.ipv4.dhcp or false)
          && ! (uplinks.${name}.ipv6.enable or true)
          && ! (uplinks.${name}.ipv6.acceptRA or false);
        bridgeUsesDhcp = bridgeName:
          let cfg = networks."30-${bridgeName}".networkConfig or { };
          in (cfg.DHCP or null) == "ipv4"
            && (cfg.IPv6AcceptRA or false)
            && (cfg.LinkLocalAddressing or null) == "ipv6";
        managementBridgeUsesDhcp = bridgeName:
          let cfg = networks."30-${bridgeName}".networkConfig or { };
          in (cfg.DHCP or null) == "ipv4"
            && ! (cfg.IPv6AcceptRA or false)
            && (cfg.LinkLocalAddressing or null) == "no";
        hasVlanAttachment = vlan:
          let name = "eth0.${toString vlan}";
          in (netdevs."11-${name}".netdevConfig.Kind or null) == "vlan"
            && (netdevs."11-${name}".vlanConfig.Id or null) == vlan
            && (networks."20-eth0".networkConfig.VLAN or [ ]) == [ "eth0.2" "eth0.4" "eth0.5" ]
            && (networks."21-${name}".networkConfig.Bridge or null) == uplinks.${uplinkNameForVlan vlan}.bridge;
        netdevs = host.renderedHost.netdevs;
        managementUplink = uplinkNameForVlan 2;
        vlan4Uplink = uplinkNameForVlan 4;
        vlan5Uplink = uplinkNameForVlan 5;
      in
        managementUplink != null
        && vlan4Uplink != null
        && vlan5Uplink != null
        && managementUplinkIsVlanDhcp managementUplink
        && uplinkIsVlanDhcp vlan4Uplink
        && uplinkIsVlanDhcp vlan5Uplink
        && managementBridgeUsesDhcp uplinks.${managementUplink}.bridge
        && bridgeUsesDhcp uplinks.${vlan4Uplink}.bridge
        && bridgeUsesDhcp uplinks.${vlan5Uplink}.bridge
        && hasVlanAttachment 2
        && hasVlanAttachment 4
        && hasVlanAttachment 5
    ' | grep -qx true

echo "PASS host-uplink-vlan-dhcp"
