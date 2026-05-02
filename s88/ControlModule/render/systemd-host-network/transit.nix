{ lib, common }:

let
  inherit (common) transitBridges transitNames uplinks transitNameRendered;
in
{
  transitNetdevs = builtins.listToAttrs (
    map (
      transitName:
      let rendered = transitNameRendered transitName;
      in
      {
        name = "40-${rendered}";
        value.netdevConfig = {
          Name = rendered;
          Kind = "bridge";
        };
      }
    ) transitNames
  );

  transitNetworks = builtins.listToAttrs (
    lib.concatMap (
      transitName:
      let
        transit = transitBridges.${transitName};
        rendered = transitNameRendered transitName;
        parentUplink = transit.parentUplink or null;
      in
      [
        {
          name = "50-${rendered}";
          value = {
            matchConfig.Name = rendered;
            linkConfig = {
              ActivationPolicy = "always-up";
              RequiredForOnline = "no";
            };
            networkConfig.ConfigureWithoutCarrier = true;
          };
        }
      ]
      ++ lib.optionals (parentUplink != null && builtins.hasAttr parentUplink uplinks && (uplinks.${parentUplink}.mode or "") == "trunk") [
        {
          name = "51-${uplinks.${parentUplink}.bridge}.${toString transit.vlan}";
          value = {
            matchConfig.Name = "${uplinks.${parentUplink}.bridge}.${toString transit.vlan}";
            linkConfig = {
              ActivationPolicy = "always-up";
              RequiredForOnline = "no";
            };
            networkConfig = {
              Bridge = rendered;
              ConfigureWithoutCarrier = true;
              LinkLocalAddressing = "no";
              IPv6AcceptRA = false;
            };
          };
        }
      ]
    ) transitNames
  );
}
