{ lib, common, vlans }:

let
  inherit
    (common)
    uplinks
    transitBridges
    uplinkNames
    transitNamesForUplink
    vlanIfNameFor
    ;
  inherit (vlans) bridgeNetworkVlanNames bridgeNetworkVlanIfNameFor bridgeNetworkVlanParentFor;

  bridgeNetworkFor =
    uplink:
    let originalBridge = if builtins.isString (uplink.originalBridge or null) then uplink.originalBridge else uplink.bridge;
    in if builtins.hasAttr originalBridge common.bridgeNetworks then common.bridgeNetworks.${originalBridge} else { ConfigureWithoutCarrier = true; };
in
{
  uplinkBridgeNetdevs = builtins.listToAttrs (
    lib.concatMap (
      uplinkName:
      let
        uplink = uplinks.${uplinkName};
        vlanIfName = vlanIfNameFor uplinkName;
      in
      [
        {
          name = "10-${uplink.bridge}";
          value.netdevConfig = {
            Name = uplink.bridge;
            Kind = "bridge";
          };
        }
      ]
      ++ lib.optionals ((uplink.mode or "") == "vlan") [
        {
          name = "11-${vlanIfName}";
          value = {
            netdevConfig = {
              Name = vlanIfName;
              Kind = "vlan";
            };
            vlanConfig.Id = uplink.vlan;
          };
        }
      ]
      ++ lib.optionals ((uplink.mode or "") == "trunk") (
        map (
          transitName:
          let transit = transitBridges.${transitName};
          in
          {
            name = "12-${common.transitNameRendered transitName}";
            value = {
              netdevConfig = {
                Name = "${uplink.bridge}.${toString transit.vlan}";
                Kind = "vlan";
              };
              vlanConfig.Id = transit.vlan;
            };
          }
        ) (transitNamesForUplink uplinkName)
      )
    ) uplinkNames
  );

  uplinkParentNetworks = builtins.listToAttrs (
    map (
      parentIf:
      let
        uplinksOnParent = lib.filter (uplinkName: uplinks.${uplinkName}.parent == parentIf) uplinkNames;
        bridgeVlansOnParent = lib.filter (bridgeName: bridgeNetworkVlanParentFor bridgeName == parentIf) bridgeNetworkVlanNames;
        vlanChildren = lib.filter (name: name != null) (map vlanIfNameFor uplinksOnParent) ++ map bridgeNetworkVlanIfNameFor bridgeVlansOnParent;
        directBridgeUplinks = lib.filter (uplinkName: (uplinks.${uplinkName}.mode or "") != "vlan") uplinksOnParent;
        _singleDirectBridge =
          if builtins.length directBridgeUplinks <= 1 then
            true
          else
            throw ''
              s88/CM/network/render/systemd-host-network.nix: multiple non-vlan uplinks on parent '${parentIf}' are not supported
              uplinks: ${builtins.concatStringsSep "\n - " ([ "" ] ++ directBridgeUplinks)}
            '';
      in
      builtins.seq _singleDirectBridge {
        name = "20-${parentIf}";
        value = {
          matchConfig.Name = parentIf;
          linkConfig = {
            ActivationPolicy = "always-up";
            RequiredForOnline = "no";
          };
          networkConfig = {
            ConfigureWithoutCarrier = true;
            LinkLocalAddressing = "no";
            IPv6AcceptRA = false;
          }
          // lib.optionalAttrs (vlanChildren != [ ]) { VLAN = vlanChildren; }
          // lib.optionalAttrs (builtins.length directBridgeUplinks == 1) {
            Bridge = uplinks.${builtins.head directBridgeUplinks}.bridge;
          };
        };
      }
    ) (
      lib.unique (
        lib.filter builtins.isString (map (uplinkName: uplinks.${uplinkName}.parent or null) uplinkNames)
        ++ map bridgeNetworkVlanParentFor bridgeNetworkVlanNames
      )
    )
  );

  uplinkBridgeAttachmentNetworks =
    (builtins.listToAttrs (
      lib.concatMap (
        uplinkName:
        let
          uplink = uplinks.${uplinkName};
          vlanIfName = vlanIfNameFor uplinkName;
        in
        lib.optionals ((uplink.mode or "") == "vlan") [
          {
            name = "21-${vlanIfName}";
            value = {
              matchConfig.Name = vlanIfName;
              linkConfig = {
                ActivationPolicy = "always-up";
                RequiredForOnline = "no";
              };
              networkConfig = {
                Bridge = uplink.bridge;
                ConfigureWithoutCarrier = true;
                LinkLocalAddressing = "no";
                IPv6AcceptRA = false;
              };
            };
          }
        ]
      ) uplinkNames
    ))
    // vlans.bridgeNetworkVlanAttachmentNetworks;

  uplinkBridgeNetworks = builtins.listToAttrs (
    map (
      uplinkName:
      let
        uplink = uplinks.${uplinkName};
        transitNamesOnUplink = transitNamesForUplink uplinkName;
        baseBridgeNetworkConfig = bridgeNetworkFor uplink;
        ipv4Dhcp = uplink ? ipv4 && builtins.isAttrs uplink.ipv4 && ((uplink.ipv4.dhcp or false) || (uplink.ipv4.method or null) == "dhcp");
        ipv6Dhcp = uplink ? ipv6 && builtins.isAttrs uplink.ipv6 && ((uplink.ipv6.dhcp or false) || (uplink.ipv6.method or null) == "dhcp" || (uplink.ipv6.method or null) == "dhcp6");
        ipv6AcceptRA = uplink ? ipv6 && builtins.isAttrs uplink.ipv6 && ((uplink.ipv6.acceptRA or false) || (uplink.ipv6.method or null) == "slaac");
        isManagementUplink = uplinkName == "management" || (uplink.management or false) || (uplink.role or null) == "management";
        hostIpv4Dhcp = isManagementUplink && ipv4Dhcp;
        hostIpv6Dhcp = isManagementUplink && ipv6Dhcp;
        hostIpv6AcceptRA = isManagementUplink && ipv6AcceptRA;
        dhcpMode = if hostIpv4Dhcp && hostIpv6Dhcp then "yes" else if hostIpv4Dhcp then "ipv4" else if hostIpv6Dhcp then "ipv6" else "no";
      in
      {
        name = "30-${uplink.bridge}";
        value = {
          matchConfig.Name = uplink.bridge;
          linkConfig = {
            ActivationPolicy = "always-up";
            RequiredForOnline = "no";
          };
          networkConfig = {
            ConfigureWithoutCarrier = true;
            DHCP = dhcpMode;
            LinkLocalAddressing = if hostIpv6Dhcp || hostIpv6AcceptRA then "ipv6" else "no";
            IPv6AcceptRA = hostIpv6AcceptRA;
          }
          // baseBridgeNetworkConfig
          // lib.optionalAttrs ((uplink.mode or "") == "trunk" && transitNamesOnUplink != [ ]) {
            VLAN = map (transitName: "${uplink.bridge}.${toString transitBridges.${transitName}.vlan}") transitNamesOnUplink;
          };
          dhcpV4Config = lib.optionalAttrs hostIpv4Dhcp { UseDNS = false; };
        };
      }
    ) uplinkNames
  );
}
