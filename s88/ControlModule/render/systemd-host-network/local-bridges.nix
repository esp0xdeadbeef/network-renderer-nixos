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
          # CPM-created WAN bridges (not in inventory bridgeNetworks) auto-get
          # a gateway IP so containers can reach the internet through the host.
          # FS-380-HDS-020-SDS-010-SMS-060 (core WAN IP assignment).
          else if !(builtins.hasAttr originalName bridgeNetworks) && originalName != "lo"
          then [ "10.11.0.1/24" ]
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
