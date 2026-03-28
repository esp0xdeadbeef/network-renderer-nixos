{ lib }:

let
  sortedAttrNames = attrs: lib.sort builtins.lessThan (builtins.attrNames attrs);
in
{
  renderTenantBridges =
    {
      tenantBridges ? { },
      shorten,
      ensureUnique,
    }:
    let
      bridgeNamesRaw =
        lib.unique (
          lib.filter builtins.isString (builtins.attrNames tenantBridges)
        );

      bridgeNameMap = ensureUnique bridgeNamesRaw;

      bridgeNames = map (n: bridgeNameMap.${n}) bridgeNamesRaw;

      netdevs =
        builtins.listToAttrs (
          map
            (bridgeName: {
              name = "40-${bridgeName}";
              value = {
                netdevConfig = {
                  Name = bridgeName;
                  Kind = "bridge";
                };
              };
            })
            bridgeNames
        );

      networks =
        builtins.listToAttrs (
          map
            (bridgeName: {
              name = "50-${bridgeName}";
              value = {
                matchConfig.Name = bridgeName;
                networkConfig = {
                  ConfigureWithoutCarrier = true;
                };
              };
            })
            bridgeNames
        );
    in
    {
      inherit netdevs networks bridgeNameMap;
    };
}
