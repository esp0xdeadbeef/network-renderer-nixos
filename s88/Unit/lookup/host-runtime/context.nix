{
  lib,
  hostName,
  cpm ? null,
  inventory ? { },
  hostContext ? null,
  file ? "s88/Unit/lookup/host-runtime.nix",
}:

let
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

  ensureAttrs = value: if builtins.isAttrs value then value else { };

  cpmRoot =
    if cpm == null then
      { }
    else if
      builtins.isAttrs cpm && cpm ? control_plane_model && builtins.isAttrs cpm.control_plane_model
    then
      cpm.control_plane_model
    else if builtins.isAttrs cpm then
      cpm
    else
      { };

  cpmRenderHosts =
    if
      cpmRoot ? render
      && builtins.isAttrs cpmRoot.render
      && cpmRoot.render ? hosts
      && builtins.isAttrs cpmRoot.render.hosts
    then
      cpmRoot.render.hosts
    else if cpmRoot ? renderHosts && builtins.isAttrs cpmRoot.renderHosts then
      cpmRoot.renderHosts
    else
      { };

  cpmDeploymentHosts =
    if
      cpmRoot ? deployment
      && builtins.isAttrs cpmRoot.deployment
      && cpmRoot.deployment ? hosts
      && builtins.isAttrs cpmRoot.deployment.hosts
    then
      cpmRoot.deployment.hosts
    else if cpmRoot ? hosts && builtins.isAttrs cpmRoot.hosts then
      cpmRoot.hosts
    else
      { };

  cpmRealizationNodes =
    if
      cpmRoot ? realization
      && builtins.isAttrs cpmRoot.realization
      && cpmRoot.realization ? nodes
      && builtins.isAttrs cpmRoot.realization.nodes
    then
      cpmRoot.realization.nodes
    else if cpmRoot ? nodes && builtins.isAttrs cpmRoot.nodes then
      cpmRoot.nodes
    else
      { };

  renderHostConfig =
    if
      builtins.hasAttr requestedHostName cpmRenderHosts
      && builtins.isAttrs cpmRenderHosts.${requestedHostName}
    then
      cpmRenderHosts.${requestedHostName}
    else
      { };

  deploymentHostNameFromRenderHost =
    if
      renderHostConfig ? deploymentHostName && builtins.isString renderHostConfig.deploymentHostName
    then
      renderHostConfig.deploymentHostName
    else if renderHostConfig ? deploymentHost && builtins.isString renderHostConfig.deploymentHost then
      renderHostConfig.deploymentHost
    else if
      renderHostConfig ? deploymentHostDef
      && builtins.isAttrs renderHostConfig.deploymentHostDef
      && renderHostConfig.deploymentHostDef ? name
      && builtins.isString renderHostConfig.deploymentHostDef.name
    then
      renderHostConfig.deploymentHostDef.name
    else
      null;

  deploymentHostName =
    if deploymentHostNameFromRenderHost != null then
      deploymentHostNameFromRenderHost
    else
      requestedHostName;

  deploymentHost =
    if
      builtins.hasAttr deploymentHostName cpmDeploymentHosts
      && builtins.isAttrs cpmDeploymentHosts.${deploymentHostName}
    then
      cpmDeploymentHosts.${deploymentHostName}
    else
      { };

  resolvedHostContext =
    if hostContext != null && builtins.isAttrs hostContext && hostContext != { } then
      hostContext // { hostname = requestedHostName; }
    else if inventory != { } then

      {
        hostname = requestedHostName;
        renderHosts = { };
        renderHostConfig = { };
        deploymentHosts = ensureAttrs (inventory.deployment.hosts or { });
        deploymentHostNames = [ requestedHostName ];
        realizationNodes =
          if
            inventory ? realization
            && builtins.isAttrs inventory.realization
            && inventory.realization ? nodes
            && builtins.isAttrs inventory.realization.nodes
          then
            inventory.realization.nodes
          else
            { };
        deploymentHostName = requestedHostName;
        deploymentHost = { };
        realizationNode = null;
      }
    else

      {
        hostname = requestedHostName;
        renderHosts = cpmRenderHosts;
        inherit renderHostConfig;
        deploymentHosts = cpmDeploymentHosts;
        deploymentHostNames = [ deploymentHostName ];
        realizationNodes = cpmRealizationNodes;
        inherit deploymentHostName deploymentHost;
        realizationNode = null;
      };

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
