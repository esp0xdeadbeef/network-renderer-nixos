{ lib
, runtimeContext
, normalizedRuntimeTargets
, hostRenderings
, deploymentHostNames
, controlPlane
, resolvedInventory
,
}:

let
  sortedAttrNames = attrs: lib.sort builtins.lessThan (builtins.attrNames attrs);

  attachTargetForUnitInterface =
    { hostRendering
    , unitName
    , ifName
    , iface
    ,
    }:
    let
      matches = lib.filter
        (
          target:
          (target.unitName or null) == unitName
          && (
            (target.ifName or null) == ifName
            || ((target.renderedIfName or null) == (iface.renderedIfName or null))
            || ((target.interface.renderedIfName or null) == (iface.renderedIfName or null))
            || ((target.hostBridgeName or null) == (iface.hostBridge or null))
          )
        )
        (hostRendering.attachTargets or [ ]);
    in
    if builtins.length matches == 1 then builtins.head matches else null;
in
unitName:
let
  deploymentHostName = runtimeContext.deploymentHostForUnit {
    cpm = controlPlane;
    inventory = resolvedInventory;
    inherit unitName;
    file = "s88/CM/network/render/dry-config-model.nix";
  };

  hostRendering =
    if builtins.hasAttr deploymentHostName hostRenderings then
      hostRenderings.${deploymentHostName}
    else
      throw ''
        s88/CM/network/render/dry-config-model.nix: unit '${unitName}' references unknown deployment host '${deploymentHostName}'
      '';

  bridgeNameMap = hostRendering.bridgeNameMap or { };
  interfaces = normalizedRuntimeTargets.${unitName}.interfaces or { };

  globalBridgeNameMap = lib.foldl'
    (
      acc: hostName: acc // (hostRenderings.${hostName}.bridgeNameMap or { })
    )
    { }
    deploymentHostNames;
in
builtins.listToAttrs (
  map
    (
      ifName:
      let
        iface = interfaces.${ifName};

        attachTarget = attachTargetForUnitInterface {
          inherit
            hostRendering
            unitName
            ifName
            iface
            ;
        };

        renderedHostBridgeName =
          if
            attachTarget != null
            && attachTarget ? renderedHostBridgeName
            && builtins.isString attachTarget.renderedHostBridgeName
          then
            attachTarget.renderedHostBridgeName
          else if builtins.hasAttr iface.hostBridge bridgeNameMap then
            bridgeNameMap.${iface.hostBridge}
          else if builtins.hasAttr iface.hostBridge globalBridgeNameMap then
            globalBridgeNameMap.${iface.hostBridge}
          else
            throw ''
              s88/CM/network/render/dry-config-model.nix: missing rendered bridge for '${iface.hostBridge}' (unit '${unitName}', interface '${ifName}')

              deploymentHostName: ${deploymentHostName}

              local bridgeNameMap keys:
              ${builtins.toJSON (sortedAttrNames bridgeNameMap)}

              global bridgeNameMap keys:
              ${builtins.toJSON (sortedAttrNames globalBridgeNameMap)}
            '';
      in
      {
        name = ifName;
        value = iface // {
          inherit renderedHostBridgeName;
        };
      }
    )
    (sortedAttrNames interfaces)
)
