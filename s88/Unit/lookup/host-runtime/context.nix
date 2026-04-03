{
  lib,
  hostName,
  inventory ? { },
  hostContext ? null,
  file ? "s88/Unit/lookup/host-runtime.nix",
}:

let
  hostQuery = import ../../../ControlModule/lookup/host-query.nix { inherit lib; };

  requestedHostName =
    if
      hostContext != null
      && builtins.isAttrs hostContext
      && hostContext ? hostname
      && builtins.isString hostContext.hostname
    then
      hostContext.hostname
    else
      hostName;

  resolvedHostContext =
    if hostContext != null && builtins.isAttrs hostContext && hostContext != { } then
      hostContext // { hostname = requestedHostName; }
    else if inventory != { } then
      hostQuery.hostContextForHost {
        inherit inventory file;
        hostname = requestedHostName;
      }
    else
      {
        hostname = requestedHostName;
        renderHosts = { };
        renderHostConfig = { };
        deploymentHosts = { };
        deploymentHostNames = [ requestedHostName ];
        realizationNodes = { };
        deploymentHostName = requestedHostName;
        deploymentHost = { };
        realizationNode = null;
      };

  deploymentHostName =
    if
      resolvedHostContext ? deploymentHostName && builtins.isString resolvedHostContext.deploymentHostName
    then
      resolvedHostContext.deploymentHostName
    else
      requestedHostName;

  deploymentHost =
    if resolvedHostContext ? deploymentHost && builtins.isAttrs resolvedHostContext.deploymentHost then
      resolvedHostContext.deploymentHost
    else
      { };

  renderHostConfig =
    if
      resolvedHostContext ? renderHostConfig && builtins.isAttrs resolvedHostContext.renderHostConfig
    then
      resolvedHostContext.renderHostConfig
    else
      { };

  realizationNodes =
    if
      inventory ? realization
      && builtins.isAttrs inventory.realization
      && inventory.realization ? nodes
      && builtins.isAttrs inventory.realization.nodes
    then
      inventory.realization.nodes
    else if
      resolvedHostContext ? realizationNodes && builtins.isAttrs resolvedHostContext.realizationNodes
    then
      resolvedHostContext.realizationNodes
    else
      { };

  effectiveHostContext = resolvedHostContext // {
    hostname = requestedHostName;
    inherit deploymentHostName;
  };
in
{
  inherit
    requestedHostName
    resolvedHostContext
    deploymentHostName
    deploymentHost
    renderHostConfig
    realizationNodes
    effectiveHostContext
    ;
}
