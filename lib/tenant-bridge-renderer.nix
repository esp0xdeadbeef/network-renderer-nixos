{ lib }:

let
  sortNames = names: lib.sort builtins.lessThan names;

  bridgeNamesRawForAttachTargets =
    attachTargets:
    sortNames (
      lib.unique (
        lib.filter builtins.isString (map (target: target.hostBridgeName or null) attachTargets)
      )
    );

  bridgeNameMapForAttachTargets =
    {
      attachTargets,
      shorten,
      ensureUnique,
    }:
    let
      bridgeNamesRaw = bridgeNamesRawForAttachTargets attachTargets;
    in
    ensureUnique bridgeNamesRaw;

  renderBridgeArtifacts =
    {
      attachTargets,
      shorten,
      ensureUnique,
    }:
    let
      bridgeNamesRaw = bridgeNamesRawForAttachTargets attachTargets;
      bridgeNameMap = bridgeNameMapForAttachTargets {
        inherit attachTargets shorten ensureUnique;
      };

      renderedBridgeNames = map (bridgeName: bridgeNameMap.${bridgeName}) bridgeNamesRaw;

      bridges = builtins.listToAttrs (
        map (bridgeName: {
          name = bridgeName;
          value = {
            originalName = bridgeName;
            renderedName = bridgeNameMap.${bridgeName};
          };
        }) bridgeNamesRaw
      );

      netdevs = builtins.listToAttrs (
        map (renderedBridgeName: {
          name = "10-${renderedBridgeName}";
          value = {
            netdevConfig = {
              Name = renderedBridgeName;
              Kind = "bridge";
            };
          };
        }) renderedBridgeNames
      );

      networks = builtins.listToAttrs (
        map (renderedBridgeName: {
          name = "30-${renderedBridgeName}";
          value = {
            matchConfig.Name = renderedBridgeName;
            linkConfig = {
              ActivationPolicy = "always-up";
              RequiredForOnline = "no";
            };
            networkConfig = {
              ConfigureWithoutCarrier = true;
            };
          };
        }) renderedBridgeNames
      );
    in
    {
      inherit
        bridgeNamesRaw
        bridgeNameMap
        bridges
        netdevs
        networks
        ;
    };

  renderedAttachTargets =
    {
      attachTargets,
      bridgeNameMap,
      shorten,
    }:
    map (
      target:
      let
        hostBridgeName = target.hostBridgeName;
      in
      target
      // {
        renderedHostBridgeName =
          if builtins.hasAttr hostBridgeName bridgeNameMap then
            bridgeNameMap.${hostBridgeName}
          else
            shorten hostBridgeName;
      }
    ) attachTargets;
in
{
  inherit
    bridgeNamesRawForAttachTargets
    bridgeNameMapForAttachTargets
    renderBridgeArtifacts
    renderedAttachTargets
    ;
}
