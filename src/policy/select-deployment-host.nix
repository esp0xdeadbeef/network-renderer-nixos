{ lib }:
{
  model,
  boxName,
}:
let
  ensureAttrs =
    name: value:
    if builtins.isAttrs value then
      value
    else
      throw "network-renderer-nixos: expected ${name} to be an attribute set";

  ensureString =
    name: value:
    if builtins.isString value && value != "" then
      value
    else
      throw "network-renderer-nixos: expected ${name} to be a non-empty string";

  deploymentHosts =
    if model ? deploymentHosts then ensureAttrs "model.deploymentHosts" model.deploymentHosts else { };

  renderHosts =
    if model ? renderHosts then ensureAttrs "model.renderHosts" model.renderHosts else { };

  deploymentHostNameFromRenderHost =
    renderHostName: renderHostDef:
    let
      renderHost = ensureAttrs "render host '${renderHostName}'" renderHostDef;
    in
    if
      renderHost ? deploymentHost
      && builtins.isString renderHost.deploymentHost
      && renderHost.deploymentHost != ""
    then
      renderHost.deploymentHost
    else if
      renderHost ? deploymentHostName
      && builtins.isString renderHost.deploymentHostName
      && renderHost.deploymentHostName != ""
    then
      renderHost.deploymentHostName
    else if
      renderHost ? deploymentHost
      && builtins.isAttrs renderHost.deploymentHost
      && renderHost.deploymentHost ? name
      && builtins.isString renderHost.deploymentHost.name
      && renderHost.deploymentHost.name != ""
    then
      renderHost.deploymentHost.name
    else
      throw "network-renderer-nixos: render host '${renderHostName}' is missing explicit deploymentHost/deploymentHostName";

  resolvedDeploymentHostName =
    if builtins.hasAttr boxName deploymentHosts then
      boxName
    else if builtins.hasAttr boxName renderHosts then
      deploymentHostNameFromRenderHost boxName renderHosts.${boxName}
    else
      throw ''
        network-renderer-nixos: deployment host or render host '${boxName}' is missing from control-plane output
        knownDeploymentHosts=${builtins.toJSON (lib.sort builtins.lessThan (builtins.attrNames deploymentHosts))}
        knownRenderHosts=${builtins.toJSON (lib.sort builtins.lessThan (builtins.attrNames renderHosts))}
      '';

  deploymentHostDef =
    if builtins.hasAttr resolvedDeploymentHostName deploymentHosts then
      deploymentHosts.${resolvedDeploymentHostName}
    else
      throw ''
        network-renderer-nixos: resolved deployment host '${resolvedDeploymentHostName}' for selector '${boxName}' is missing from control-plane output
        knownDeploymentHosts=${builtins.toJSON (lib.sort builtins.lessThan (builtins.attrNames deploymentHosts))}
      '';
in
{
  name = resolvedDeploymentHostName;
  definition = deploymentHostDef;
}
