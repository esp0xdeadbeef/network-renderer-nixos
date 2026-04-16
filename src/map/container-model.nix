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

  runtimeTargetsForNode =
    nodeName: node:
    let
      enterpriseName = enterpriseNameForNode node;
      siteName = siteNameForNode node;
      logicalName = logicalNameForNode nodeName node;

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

      matchingNames = lib.filter (
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
        in
        placementHost == boxName && targetLogicalName == logicalName
      ) (sortedAttrNames siteRoot);
    in
    if builtins.length matchingNames <= 1 then
      map (name: siteRoot.${name}) matchingNames
    else
      throw "network-renderer-nixos: deployment host '${boxName}' resolves logical node '${logicalName}' to multiple runtime targets";

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

  effectiveInterfaceCandidatesForPort =
    portName: port: effectiveInterfaces:
    let
      interfaceNameFromPort =
        if
          builtins.isAttrs port
          && port ? interface
          && builtins.isAttrs port.interface
          && port.interface ? name
          && builtins.isString port.interface.name
          && port.interface.name != ""
        then
          port.interface.name
        else
          null;

      linkFromPort =
        if builtins.isAttrs port && port ? link && builtins.isString port.link && port.link != "" then
          port.link
        else
          null;

      matches = lib.filter (
        interfaceName:
        let
          candidate = effectiveInterfaces.${interfaceName};

          runtimeIfName =
            if
              builtins.isAttrs candidate
              && candidate ? runtimeIfName
              && builtins.isString candidate.runtimeIfName
              && candidate.runtimeIfName != ""
            then
              candidate.runtimeIfName
            else
              null;

          renderedIfName =
            if
              builtins.isAttrs candidate
              && candidate ? renderedIfName
              && builtins.isString candidate.renderedIfName
              && candidate.renderedIfName != ""
            then
              candidate.renderedIfName
            else
              null;

          containerInterfaceName =
            if
              builtins.isAttrs candidate
              && candidate ? containerInterfaceName
              && builtins.isString candidate.containerInterfaceName
              && candidate.containerInterfaceName != ""
            then
              candidate.containerInterfaceName
            else
              null;

          sourceInterface =
            if
              builtins.isAttrs candidate
              && candidate ? sourceInterface
              && builtins.isString candidate.sourceInterface
              && candidate.sourceInterface != ""
            then
              candidate.sourceInterface
            else
              null;
        in
        interfaceName == portName
        || (interfaceNameFromPort != null && interfaceName == interfaceNameFromPort)
        || (runtimeIfName != null && runtimeIfName == portName)
        || (
          runtimeIfName != null && interfaceNameFromPort != null && runtimeIfName == interfaceNameFromPort
        )
        || (renderedIfName != null && renderedIfName == portName)
        || (
          renderedIfName != null && interfaceNameFromPort != null && renderedIfName == interfaceNameFromPort
        )
        || (containerInterfaceName != null && containerInterfaceName == portName)
        || (
          containerInterfaceName != null
          && interfaceNameFromPort != null
          && containerInterfaceName == interfaceNameFromPort
        )
        || (linkFromPort != null && sourceInterface != null && sourceInterface == linkFromPort)
      ) (sortedAttrNames effectiveInterfaces);
    in
    matches;

  effectiveInterfaceForPort =
    nodeName: node: portName: port:
    let
      effectiveInterfaces = effectiveInterfacesForNode nodeName node;
    in
    if effectiveInterfaces == null then
      null
    else
      let
        matches = effectiveInterfaceCandidatesForPort portName port effectiveInterfaces;
      in
      if builtins.length matches == 0 then
        null
      else if builtins.length matches == 1 then
        effectiveInterfaces.${builtins.head matches}
      else
        throw "network-renderer-nixos: deployment host '${boxName}' port '${portName}' resolves to multiple effective interfaces";

  interfaceDataForPort =
    nodeName: node: portName: port:
    let
      effectiveInterface = effectiveInterfaceForPort nodeName node portName port;

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
