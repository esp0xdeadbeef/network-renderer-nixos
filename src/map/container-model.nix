{ lib }:
{
  model,
  boxName,
  deploymentHostDef ? { },
  disabled ? { },
  defaults ? { },
}:
let
  sortedAttrNames = attrs: lib.sort builtins.lessThan (builtins.attrNames attrs);

  deploymentDefaults =
    if
      builtins.isAttrs deploymentHostDef
      && deploymentHostDef ? containerDefaults
      && builtins.isAttrs deploymentHostDef.containerDefaults
    then
      deploymentHostDef.containerDefaults
    else
      { };

  baseDefaults = lib.recursiveUpdate deploymentDefaults defaults;

  logicalNameForNode =
    nodeName: node:
    if
      builtins.isAttrs node
      && node ? logicalNode
      && builtins.isAttrs node.logicalNode
      && node.logicalNode ? name
      && builtins.isString node.logicalNode.name
    then
      node.logicalNode.name
    else
      nodeName;

  siteNameForNode =
    node:
    if
      builtins.isAttrs node
      && node ? logicalNode
      && builtins.isAttrs node.logicalNode
      && node.logicalNode ? site
      && builtins.isString node.logicalNode.site
    then
      node.logicalNode.site
    else
      null;

  enterpriseNameForNode =
    node:
    if
      builtins.isAttrs node
      && node ? logicalNode
      && builtins.isAttrs node.logicalNode
      && node.logicalNode ? enterprise
      && builtins.isString node.logicalNode.enterprise
    then
      node.logicalNode.enterprise
    else
      null;

  runtimeRoleForNode =
    node:
    if
      builtins.isAttrs node
      && node ? logicalNode
      && builtins.isAttrs node.logicalNode
      && node.logicalNode ? role
      && builtins.isString node.logicalNode.role
    then
      node.logicalNode.role
    else
      null;

  directBridgeNameFor =
    node: port:
    let
      siteName = siteNameForNode node;
      linkName = if port ? link && builtins.isString port.link then port.link else null;
    in
    if linkName == null then
      null
    else if siteName == null || siteName == "" then
      linkName
    else
      "${siteName}--${linkName}";

  hostBridgeForPort =
    node: port:
    if builtins.isAttrs port && port ? attach && builtins.isAttrs port.attach then
      if
        port.attach ? kind
        && port.attach.kind == "bridge"
        && port.attach ? bridge
        && builtins.isString port.attach.bridge
      then
        port.attach.bridge
      else if port.attach ? kind && port.attach.kind == "direct" then
        directBridgeNameFor node port
      else
        null
    else
      null;

  containerInterfaceNameForPort =
    portName: port:
    if
      builtins.isAttrs port
      && port ? interface
      && builtins.isAttrs port.interface
      && port.interface ? name
      && builtins.isString port.interface.name
    then
      port.interface.name
    else
      portName;

  shortRuntimeTargetNameForNode =
    nodeName:
    let
      match = builtins.match "^[^-]+-[^-]+-[^-]+-(.*)$" nodeName;
    in
    if match == null then null else builtins.head match;

  resolveMatchingRuntimeTargets =
    nodeName: node: siteRoot:
    let
      logicalName = logicalNameForNode nodeName node;
      runtimeRole = runtimeRoleForNode node;
      shortRuntimeTargetName = shortRuntimeTargetNameForNode nodeName;

      candidateNames = lib.unique (
        lib.filter (name: name != null && name != "") [
          logicalName
          shortRuntimeTargetName
        ]
      );

      runtimeTargetNames = sortedAttrNames siteRoot;

      filterNames =
        predicate:
        lib.filter (
          runtimeTargetName:
          let
            runtimeTarget = siteRoot.${runtimeTargetName};

            placementHost =
              if
                builtins.isAttrs runtimeTarget
                && runtimeTarget ? placement
                && builtins.isAttrs runtimeTarget.placement
                && runtimeTarget.placement ? host
                && builtins.isString runtimeTarget.placement.host
              then
                runtimeTarget.placement.host
              else
                null;

            targetLogicalName =
              if
                builtins.isAttrs runtimeTarget
                && runtimeTarget ? logicalNode
                && builtins.isAttrs runtimeTarget.logicalNode
                && runtimeTarget.logicalNode ? name
                && builtins.isString runtimeTarget.logicalNode.name
              then
                runtimeTarget.logicalNode.name
              else
                null;

            targetRole =
              if
                builtins.isAttrs runtimeTarget
                && runtimeTarget ? logicalNode
                && builtins.isAttrs runtimeTarget.logicalNode
                && runtimeTarget.logicalNode ? role
                && builtins.isString runtimeTarget.logicalNode.role
              then
                runtimeTarget.logicalNode.role
              else if
                builtins.isAttrs runtimeTarget && runtimeTarget ? role && builtins.isString runtimeTarget.role
              then
                runtimeTarget.role
              else
                null;
          in
          placementHost == boxName
          && predicate {
            inherit
              runtimeTargetName
              targetLogicalName
              targetRole
              ;
          }
        ) runtimeTargetNames;

      exactByName = filterNames (candidate: lib.elem candidate.runtimeTargetName candidateNames);
      exactByLogicalName = filterNames (candidate: lib.elem candidate.targetLogicalName candidateNames);
      exactByRole =
        if runtimeRole == null then [ ] else filterNames (candidate: candidate.targetRole == runtimeRole);

      resolvedNames =
        if builtins.length exactByName == 1 then
          exactByName
        else if builtins.length exactByLogicalName == 1 then
          exactByLogicalName
        else if builtins.length exactByRole == 1 then
          exactByRole
        else if builtins.length exactByName > 1 then
          throw "network-renderer-nixos: deployment host '${boxName}' resolves node '${nodeName}' to multiple runtime targets by name"
        else if builtins.length exactByLogicalName > 1 then
          throw "network-renderer-nixos: deployment host '${boxName}' resolves node '${nodeName}' to multiple runtime targets by logical name"
        else if builtins.length exactByRole > 1 then
          throw "network-renderer-nixos: deployment host '${boxName}' resolves node '${nodeName}' to multiple runtime targets by role"
        else
          [ ];
    in
    map (name: siteRoot.${name}) resolvedNames;

  runtimeTargetsForNode =
    nodeName: node:
    let
      enterpriseName = enterpriseNameForNode node;
      siteName = siteNameForNode node;

      siteRoot =
        if
          enterpriseName != null
          && siteName != null
          && model ? siteData
          && builtins.isAttrs model.siteData
          && builtins.hasAttr enterpriseName model.siteData
          && builtins.isAttrs model.siteData.${enterpriseName}
          && builtins.hasAttr siteName model.siteData.${enterpriseName}
          && builtins.isAttrs model.siteData.${enterpriseName}.${siteName}
          && model.siteData.${enterpriseName}.${siteName} ? runtimeTargets
          && builtins.isAttrs model.siteData.${enterpriseName}.${siteName}.runtimeTargets
        then
          model.siteData.${enterpriseName}.${siteName}.runtimeTargets
        else
          { };
    in
    resolveMatchingRuntimeTargets nodeName node siteRoot;

  effectiveInterfacesForNode =
    nodeName: node:
    let
      runtimeTargets = runtimeTargetsForNode nodeName node;
    in
    if runtimeTargets == [ ] then
      null
    else
      let
        runtimeTarget = builtins.head runtimeTargets;
      in
      if
        builtins.isAttrs runtimeTarget
        && runtimeTarget ? effectiveRuntimeRealization
        && builtins.isAttrs runtimeTarget.effectiveRuntimeRealization
        && runtimeTarget.effectiveRuntimeRealization ? interfaces
        && builtins.isAttrs runtimeTarget.effectiveRuntimeRealization.interfaces
      then
        runtimeTarget.effectiveRuntimeRealization.interfaces
      else
        null;

  interfaceDataForPort =
    nodeName: node: portName: port:
    let
      effectiveInterfaces = effectiveInterfacesForNode nodeName node;

      effectiveInterface =
        if effectiveInterfaces != null && builtins.hasAttr portName effectiveInterfaces then
          effectiveInterfaces.${portName}
        else
          null;

      containerInterfaceName =
        if
          effectiveInterface != null
          && builtins.isAttrs effectiveInterface
          && effectiveInterface ? runtimeIfName
          && builtins.isString effectiveInterface.runtimeIfName
          && effectiveInterface.runtimeIfName != ""
        then
          effectiveInterface.runtimeIfName
        else if
          effectiveInterface != null
          && builtins.isAttrs effectiveInterface
          && effectiveInterface ? renderedIfName
          && builtins.isString effectiveInterface.renderedIfName
          && effectiveInterface.renderedIfName != ""
        then
          effectiveInterface.renderedIfName
        else if
          effectiveInterface != null
          && builtins.isAttrs effectiveInterface
          && effectiveInterface ? containerInterfaceName
          && builtins.isString effectiveInterface.containerInterfaceName
          && effectiveInterface.containerInterfaceName != ""
        then
          effectiveInterface.containerInterfaceName
        else
          containerInterfaceNameForPort portName port;
    in
    {
      hostBridge = hostBridgeForPort node port;
      inherit containerInterfaceName;
    }
    // lib.optionalAttrs (effectiveInterface != null && builtins.isAttrs effectiveInterface) {
      interface = effectiveInterface;
    }
    //
      lib.optionalAttrs
        (
          effectiveInterface == null
          && builtins.isAttrs port
          && port ? interface
          && builtins.isAttrs port.interface
        )
        {
          interface = port.interface;
        };

  isDisabled =
    containerName: nodeName:
    builtins.isAttrs disabled
    && (
      (builtins.hasAttr containerName disabled && disabled.${containerName} == true)
      || (builtins.hasAttr nodeName disabled && disabled.${nodeName} == true)
    );

  containerEntries = lib.concatMap (
    nodeName:
    let
      node = model.realizationNodes.${nodeName};
      logicalName = logicalNameForNode nodeName node;
      platform = node.platform or null;
      deploymentHostName = node.host or null;
      ports =
        if builtins.isAttrs node && node ? ports && builtins.isAttrs node.ports then node.ports else { };
      interfaces = lib.mapAttrs (portName: port: interfaceDataForPort nodeName node portName port) ports;
      containerName = logicalName;
      runtimeRole = runtimeRoleForNode node;
    in
    if
      platform == "nixos-container"
      && deploymentHostName == boxName
      && !(isDisabled containerName nodeName)
    then
      [
        {
          name = containerName;
          value = lib.recursiveUpdate baseDefaults {
            inherit
              containerName
              nodeName
              logicalName
              deploymentHostName
              interfaces
              runtimeRole
              ;
          };
        }
      ]
    else
      [ ]
  ) (sortedAttrNames model.realizationNodes);

  containerNames = map (entry: entry.name) containerEntries;

  _validateUniqueContainerNames =
    if builtins.length containerNames == builtins.length (lib.unique containerNames) then
      true
    else
      throw "network-renderer-nixos: deployment host '${boxName}' resolves to duplicate container names";
in
builtins.seq _validateUniqueContainerNames {
  renderHostName = boxName;
  containers = builtins.listToAttrs containerEntries;
  debug = {
    matchedNodeNames = map (entry: entry.value.nodeName) containerEntries;
    containerNames = containerNames;
  };
}
