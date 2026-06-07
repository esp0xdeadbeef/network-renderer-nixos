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
  attrsOrEmpty = value: if builtins.isAttrs value then value else { };

  isSelectorRelationRule =
    rule:
    let
      relationId = rule.relationId or "";
      relationCardinality = attrsOrEmpty (rule.relationCardinality or null);
    in
    (builtins.isString relationId && builtins.match "selector-.*" relationId != null)
    || (relationCardinality.unit or null) == "selector-forwarding-rule";

  selectorRelationAuditForEndpoint =
    { unitName
    , ifName
    , iface
    , runtimeTarget
    , rule
    , side
    ,
    }:
    let
      endpoint = attrsOrEmpty (rule.${side} or null);
      cpmRuntimeInterface = endpoint.runtimeInterface or null;
      renderedIfName = iface.renderedIfName or ifName;
      candidateInterfaceNames = [
        renderedIfName
        (iface.runtimeIfName or null)
        (iface.sourceInterface or null)
        ifName
      ];
    in
    lib.optionals
      (
        builtins.isString cpmRuntimeInterface
        && builtins.elem cpmRuntimeInterface candidateInterfaceNames
        && isSelectorRelationRule rule
      )
      [
        {
          inherit unitName ifName side cpmRuntimeInterface;
          runtimeInterface = renderedIfName;
          runtimeTargetRole = runtimeTarget.role or null;
          relationId = rule.relationId or null;
          relationComment = rule.comment or null;
          relationAction = rule.action or null;
          relationDirection = rule.direction or null;
          relationPurpose = endpoint.relationPurpose or null;
          hostFacing = endpoint.hostFacing or null;
          backingRef = endpoint.backingRef or null;
          lane = endpoint.lane or null;
          relationCardinality = rule.relationCardinality or null;
        }
      ];

  selectorRelationAuditForInterface =
    { unitName
    , ifName
    , iface
    ,
    }:
    let
      runtimeTarget = normalizedRuntimeTargets.${unitName};
      forwardingIntent = attrsOrEmpty (runtimeTarget.forwardingIntent or null);
      rules =
        if builtins.isList (forwardingIntent.rules or null) then
          forwardingIntent.rules
        else
          [ ];
    in
    builtins.concatLists (
      map
        (
          rule:
          if !builtins.isAttrs rule then
            [ ]
          else
            (selectorRelationAuditForEndpoint {
              inherit unitName ifName iface runtimeTarget rule;
              side = "from";
            })
            ++ (selectorRelationAuditForEndpoint {
              inherit unitName ifName iface runtimeTarget rule;
              side = "to";
            })
        )
        rules
    );

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
        value =
          let
            selectorRelationAudit = selectorRelationAuditForInterface {
              inherit unitName ifName iface;
            };
          in
          iface
          // {
            inherit renderedHostBridgeName;
          }
          // lib.optionalAttrs (selectorRelationAudit != [ ]) {
            inherit selectorRelationAudit;
          };
      }
    )
    (sortedAttrNames interfaces)
)
