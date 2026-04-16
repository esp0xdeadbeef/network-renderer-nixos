{ lib }:
{
  model,
  boxName,
}:
let
  deploymentHosts =
    if model ? deploymentHosts && builtins.isAttrs model.deploymentHosts then
      model.deploymentHosts
    else
      { };

  renderHosts =
    if model ? renderHosts && builtins.isAttrs model.renderHosts then model.renderHosts else { };

  renderHostDef = if builtins.hasAttr boxName renderHosts then renderHosts.${boxName} else null;

  deploymentHostNameFromRenderHost =
    if renderHostDef == null then
      null
    else if
      builtins.isAttrs renderHostDef
      && renderHostDef ? deploymentHost
      && builtins.isString renderHostDef.deploymentHost
      && renderHostDef.deploymentHost != ""
    then
      renderHostDef.deploymentHost
    else if
      builtins.isAttrs renderHostDef
      && renderHostDef ? deploymentHostName
      && builtins.isString renderHostDef.deploymentHostName
      && renderHostDef.deploymentHostName != ""
    then
      renderHostDef.deploymentHostName
    else if
      builtins.isAttrs renderHostDef
      && renderHostDef ? deploymentHostDef
      && builtins.isAttrs renderHostDef.deploymentHostDef
      && renderHostDef.deploymentHostDef ? name
      && builtins.isString renderHostDef.deploymentHostDef.name
      && renderHostDef.deploymentHostDef.name != ""
    then
      renderHostDef.deploymentHostDef.name
    else if
      builtins.isAttrs renderHostDef
      && renderHostDef ? deploymentHostRef
      && builtins.isAttrs renderHostDef.deploymentHostRef
      && renderHostDef.deploymentHostRef ? name
      && builtins.isString renderHostDef.deploymentHostRef.name
      && renderHostDef.deploymentHostRef.name != ""
    then
      renderHostDef.deploymentHostRef.name
    else if
      builtins.isAttrs renderHostDef
      && renderHostDef ? deploymentHostRef
      && builtins.isString renderHostDef.deploymentHostRef
      && renderHostDef.deploymentHostRef != ""
    then
      renderHostDef.deploymentHostRef
    else if
      builtins.isAttrs renderHostDef
      && renderHostDef ? deploymentHostId
      && builtins.isString renderHostDef.deploymentHostId
      && renderHostDef.deploymentHostId != ""
    then
      renderHostDef.deploymentHostId
    else if
      builtins.isAttrs renderHostDef
      && renderHostDef ? host
      && builtins.isString renderHostDef.host
      && renderHostDef.host != ""
      && builtins.hasAttr renderHostDef.host deploymentHosts
    then
      renderHostDef.host
    else
      null;

  resolvedDeploymentHostName =
    if builtins.hasAttr boxName deploymentHosts then boxName else deploymentHostNameFromRenderHost;
in
if
  resolvedDeploymentHostName != null && builtins.hasAttr resolvedDeploymentHostName deploymentHosts
then
  {
    name = resolvedDeploymentHostName;
    definition = deploymentHosts.${resolvedDeploymentHostName};
    requestedName = boxName;
    matchedBy = if resolvedDeploymentHostName == boxName then "deploymentHost" else "renderHost";
    renderHost =
      if renderHostDef == null then
        null
      else
        {
          name = boxName;
          definition = renderHostDef;
        };
  }
else
  throw ''
    network-renderer-nixos: deployment host or render host '${boxName}' is missing from control-plane output
    knownDeploymentHosts=${builtins.toJSON (lib.sort builtins.lessThan (builtins.attrNames deploymentHosts))}
    knownRenderHosts=${builtins.toJSON (lib.sort builtins.lessThan (builtins.attrNames renderHosts))}
  ''
