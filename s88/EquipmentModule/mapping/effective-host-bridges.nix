{
  lib,
  bridgeModel,
  wanAttachment,
  transitBridgeModel,
}:

let
  sortedAttrNames = attrs: lib.sort builtins.lessThan (builtins.attrNames attrs);

  claimedRenderedBridgeNames = lib.unique (
    lib.filter builtins.isString (
      (map (
        uplinkName:
        let
          uplink = wanAttachment.uplinks.${uplinkName};
        in
        uplink.bridge or null
      ) (sortedAttrNames (wanAttachment.uplinks or { })))
      ++ (map (
        transitName:
        let
          transit = transitBridgeModel.transitBridges.${transitName};
        in
        if transit ? name && builtins.isString transit.name then transit.name else null
      ) (sortedAttrNames (transitBridgeModel.transitBridges or { })))
    )
  );

  referencedRenderedBridgeNames = lib.unique (
    lib.filter builtins.isString (
      map (target: target.renderedHostBridgeName or null) (wanAttachment.localAttachTargets or [ ])
    )
  );

  effectiveRenderedBridgeNames = lib.filter (
    renderedName: !(builtins.elem renderedName claimedRenderedBridgeNames)
  ) (
    referencedRenderedBridgeNames
    ++ lib.filter builtins.isString (
      map (
        bridgeName:
        let
          bridge = bridgeModel.bridges.${bridgeName};
        in
        if bridge.explicitDeploymentBridge or false then bridge.renderedName else null
      ) (sortedAttrNames (bridgeModel.bridges or { }))
    )
  );

  effectiveBridges = builtins.listToAttrs (
    lib.concatMap (
      bridgeName:
      let
        bridge = bridgeModel.bridges.${bridgeName};
      in
      lib.optionals (builtins.elem bridge.renderedName effectiveRenderedBridgeNames) [
        {
          name = bridgeName;
          value = bridge;
        }
      ]
    ) (sortedAttrNames (bridgeModel.bridges or { }))
  );

  effectiveBridgeNameMap = builtins.mapAttrs (_: bridge: bridge.renderedName) effectiveBridges;
in
{
  bridgeNamesRaw = sortedAttrNames effectiveBridges;
  bridgeNameMap = effectiveBridgeNameMap;
  bridges = effectiveBridges;
}
