{ lib }:
{
  model,
  renderHostName,
}:
let
  renderHostDef =
    if builtins.hasAttr renderHostName model.renderHosts then
      model.renderHosts.${renderHostName}
    else
      throw "network-renderer-nixos: render host '${renderHostName}' is missing from control-plane output";

  logicalNodeSelector =
    if
      builtins.isAttrs renderHostDef
      && renderHostDef ? logicalNodeName
      && builtins.isString renderHostDef.logicalNodeName
    then
      renderHostDef.logicalNodeName
    else if
      builtins.isAttrs renderHostDef && renderHostDef ? node && builtins.isString renderHostDef.node
    then
      renderHostDef.node
    else
      renderHostName;

  matchedNodeNames = lib.filter (
    nodeName:
    let
      node = model.realizationNodes.${nodeName};
      logicalName =
        if
          builtins.isAttrs node
          && node ? logicalNode
          && builtins.isAttrs node.logicalNode
          && node.logicalNode ? name
          && builtins.isString node.logicalNode.name
        then
          node.logicalNode.name
        else
          null;
    in
    nodeName == logicalNodeSelector || logicalName == logicalNodeSelector
  ) (builtins.attrNames model.realizationNodes);
in
if builtins.length matchedNodeNames > 1 then
  throw "network-renderer-nixos: render host '${renderHostName}' resolves to multiple realization nodes"
else
  {
    name = renderHostName;
    definition = renderHostDef;
    logicalNodeSelector = logicalNodeSelector;
    matchedNodeNames = matchedNodeNames;
  }
