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
      interfaces = lib.mapAttrs (
        portName: port:
        {
          hostBridge = hostBridgeForPort node port;
          containerInterfaceName = containerInterfaceNameForPort portName port;
        }
        //
          lib.optionalAttrs (builtins.isAttrs port && port ? interface && builtins.isAttrs port.interface)
            {
              interface = port.interface;
            }
      ) ports;
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
