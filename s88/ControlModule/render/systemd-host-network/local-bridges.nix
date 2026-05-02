{ lib, common }:

let
  inherit (common) sortedAttrNames bridges;
in
{
  localBridgeNetdevs = builtins.listToAttrs (
    map (bridgeName: {
      name = "10-${bridges.${bridgeName}.renderedName}";
      value.netdevConfig = {
        Name = bridges.${bridgeName}.renderedName;
        Kind = "bridge";
      };
    }) (sortedAttrNames bridges)
  );

  localBridgeNetworks = builtins.listToAttrs (
    map (bridgeName: {
      name = "30-${bridges.${bridgeName}.renderedName}";
      value = {
        matchConfig.Name = bridges.${bridgeName}.renderedName;
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
      };
    }) (sortedAttrNames bridges)
  );
}
