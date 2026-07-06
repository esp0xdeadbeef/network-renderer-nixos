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
            DHCP = "no";
            IPv6AcceptRA = false;
            LinkLocalAddressing = "no";
          };
          address = hostAddresses;
        };
      })
      (sortedAttrNames bridges)
  );
}
