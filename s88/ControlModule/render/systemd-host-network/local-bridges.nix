{ lib, common }:

let
  inherit (common) sortedAttrNames bridges bridgeNetworks;
in
{
  localBridgeNetdevs = builtins.listToAttrs (
    map
      (bridgeName: {
        name = "10-${bridges.${bridgeName}.renderedName}";
        value.netdevConfig = {
          Name = bridges.${bridgeName}.renderedName;
          Kind = "bridge";
        };
      })
      (sortedAttrNames bridges)
  );

  localBridgeNetworks = builtins.listToAttrs (
    map
      (bridgeName: let
        renderedName = bridges.${bridgeName}.renderedName;
        originalName = bridges.${bridgeName}.originalName or bridgeName;
        bridgeNetConfig = if builtins.hasAttr originalName bridgeNetworks
          then bridgeNetworks.${originalName}
          else {};
        ipv4Config =
          if builtins.isAttrs (bridgeNetConfig.ipv4 or null)
          then bridgeNetConfig.ipv4
          else {};
        ipv6Config =
          if builtins.isAttrs (bridgeNetConfig.ipv6 or null)
          then bridgeNetConfig.ipv6
          else {};
        ipv4Enabled = (ipv4Config.enable or true) != false;
        ipv6Enabled = (ipv6Config.enable or true) != false;
        ipv4Dhcp =
          ipv4Enabled
          && ((ipv4Config.dhcp or false) || (ipv4Config.method or null) == "dhcp");
        ipv6Dhcp =
          ipv6Enabled
          && ((ipv6Config.dhcp or false) || (ipv6Config.method or null) == "dhcp" || (ipv6Config.method or null) == "dhcp6");
        ipv6AcceptRA =
          ipv6Enabled
          && ((ipv6Config.acceptRA or false) || (ipv6Config.method or null) == "slaac");
        dhcpMode =
          if ipv4Dhcp && ipv6Dhcp then "yes"
          else if ipv4Dhcp then "ipv4"
          else if ipv6Dhcp then "ipv6"
          else "no";
        hostAddresses =
          if builtins.isList (bridgeNetConfig.hostAddresses or null)
          then lib.filter builtins.isString bridgeNetConfig.hostAddresses
          else [];
      in {
        name = "30-${renderedName}";
        value = {
          matchConfig.Name = renderedName;
          linkConfig = {
            ActivationPolicy = "always-up";
            RequiredForOnline = "no";
          };
          networkConfig = {
            ConfigureWithoutCarrier = true;
            DHCP = dhcpMode;
            IPv6AcceptRA = ipv6AcceptRA;
            LinkLocalAddressing = if ipv6Dhcp || ipv6AcceptRA then "ipv6" else "no";
          };
          address = hostAddresses;
          dhcpV4Config = lib.optionalAttrs ipv4Dhcp { UseDNS = false; };
        };
      })
      (sortedAttrNames bridges)
  );
}
