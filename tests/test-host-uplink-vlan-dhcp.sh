#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${repo_root}/tests/lib/test-common.sh"

example_root="${EXAMPLE_ROOT:-$(flake_input_path network-labs)/examples/s-router-test-three-site}"

REPO_ROOT="${repo_root}" \
INTENT_PATH="${example_root}/intent.nix" \
INVENTORY_PATH="${example_root}/inventory-nixos.nix" \
  nix eval \
    --extra-experimental-features 'nix-command flakes' \
    --impure --expr '
      let
        flake = builtins.getFlake ("path:" + builtins.getEnv "REPO_ROOT");
        lib = flake.inputs.nixpkgs.lib;
        host = flake.lib.renderer.buildHostFromPaths {
          selector = "s-router-test";
          system = "x86_64-linux";
          intentPath = builtins.getEnv "INTENT_PATH";
          inventoryPath = builtins.getEnv "INVENTORY_PATH";
        };
        clientHost = flake.lib.renderer.buildHostFromPaths {
          selector = "s-router-test-clients";
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
        hostWanBridgeIsLayer2Only = bridgeName:
          let cfg = networks."30-${bridgeName}".networkConfig or { };
          in (cfg.DHCP or null) == "no"
            && ! (cfg.IPv6AcceptRA or false)
            && (cfg.LinkLocalAddressing or null) == "no";
        managementBridgeUsesDhcp = bridgeName:
          let
            network = networks."30-${bridgeName}";
            cfg = network.networkConfig or { };
            dhcp4 = network.dhcpV4Config or { };
          in
          (cfg.DHCP or null) == "ipv4"
            && ! (cfg.IPv6AcceptRA or false)
            && (cfg.LinkLocalAddressing or null) == "no"
            && (dhcp4.UseDNS or true) == false;
        tenantBridgeRejectsHostRa = bridgeName:
          let cfg = networks."30-${bridgeName}".networkConfig or { };
          in (cfg.DHCP or null) == "no"
            && ! (cfg.IPv6AcceptRA or false)
            && (cfg.LinkLocalAddressing or null) == "no";
        hasVlanAttachment = vlan:
          let name = "eth0.${toString vlan}";
          in (netdevs."11-${name}".netdevConfig.Kind or null) == "vlan"
            && (netdevs."11-${name}".vlanConfig.Id or null) == vlan
            && lib.elem name (networks."20-eth0".networkConfig.VLAN or [ ])
            && (networks."21-${name}".networkConfig.Bridge or null) == uplinks.${uplinkNameForVlan vlan}.bridge;
        tenantVlanAttachment = bridgeName: vlan:
          let name = "eth0.${toString vlan}";
          in (netdevs."13-${name}".netdevConfig.Kind or null) == "vlan"
            && (netdevs."13-${name}".vlanConfig.Id or null) == vlan
            && lib.elem name (networks."20-eth0".networkConfig.VLAN or [ ])
            && (networks."22-${name}".networkConfig.Bridge or null) == bridgeName;
        netdevs = host.renderedHost.netdevs;
        managementUplink = uplinkNameForVlan 2;
        vlan4Uplink = uplinkNameForVlan 4;
        vlan5Uplink = uplinkNameForVlan 5;
        managementBridge =
          if managementUplink != null then uplinks.${managementUplink}.bridge else null;
        clientHostNetdevs = clientHost.renderedHost.netdevs;
        clientHostNetworks = clientHost.renderedHost.networks;
        clientHostHasTenantVlan = bridgeName: vlan:
          let name = "eth0.${toString vlan}";
          in (clientHostNetdevs."13-${name}".vlanConfig.Id or null) == vlan
            && lib.elem name (clientHostNetworks."20-eth0".networkConfig.VLAN or [ ])
            && (clientHostNetworks."22-${name}".networkConfig.Bridge or null) == bridgeName;
        collidedAccessContainer = import (builtins.toPath (
          builtins.getEnv "REPO_ROOT" + "/s88/ControlModule/render/containers/mapping.nix"
        )) {
          inherit lib;
          model = {
            interfaces.tenant-mgmt = {
              sourceKind = "tenant";
              backingRef = {
                kind = "attachment";
                name = managementBridge;
              };
              hostVethName = "access-tenant-mgmt";
              renderedHostBridgeName = "rt--tena-collided";
            };
            veths.access-tenant-mgmt.hostBridge = "rt--tena-collided";
          };
        };
      in
        managementUplink != null
        && vlan4Uplink != null
        && vlan5Uplink != null
        && managementBridge != null
        && managementUplinkIsVlanDhcp managementUplink
        && uplinkIsVlanDhcp vlan4Uplink
        && uplinkIsVlanDhcp vlan5Uplink
        && managementBridgeUsesDhcp uplinks.${managementUplink}.bridge
        && hostWanBridgeIsLayer2Only uplinks.${vlan4Uplink}.bridge
        && hostWanBridgeIsLayer2Only uplinks.${vlan5Uplink}.bridge
        && hasVlanAttachment 2
        && hasVlanAttachment 4
        && hasVlanAttachment 5
        && tenantVlanAttachment "mgmt" 300
        && tenantVlanAttachment "client" 302
        && tenantVlanAttachment "hostile" 306
        && tenantVlanAttachment "streaming" 311
        && (clientHostNetdevs."11-eth0.2".vlanConfig.Id or null) == 2
        && (clientHostNetworks."30-vlan2".networkConfig.DHCP or null) == "ipv4"
        && clientHostHasTenantVlan "client" 302
        && clientHostHasTenantVlan "hostile" 306
        && clientHostHasTenantVlan "streaming" 311
        && ! (clientHostNetdevs ? "10-vlan3")
        && ! (clientHostNetdevs ? "10-vlan1010")
        && tenantBridgeRejectsHostRa "hostile"
        && tenantBridgeRejectsHostRa "branch"
        && tenantBridgeRejectsHostRa "client"
        && tenantBridgeRejectsHostRa "admin"
        && collidedAccessContainer.veths.access-tenant-mgmt.hostBridge == managementBridge
        && collidedAccessContainer.interfaces.tenant-mgmt.renderedHostBridgeName == managementBridge
    ' | grep -qx true

echo "PASS host-uplink-vlan-dhcp"
