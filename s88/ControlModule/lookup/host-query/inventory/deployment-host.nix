{ helpers }:

{ inventory
, hostname
, file ? "s88/ControlModule/lookup/host-query.nix"
,
}:

let
  inherit (helpers)
    deploymentHostsFor
    realizationNodesFor
    renderHostsFor
    sortedAttrNames
    ;

  renderHosts = renderHostsFor inventory;

  renderHostConfig =
    if builtins.hasAttr hostname renderHosts && builtins.isAttrs renderHosts.${hostname} then
      renderHosts.${hostname}
    else
      { };

  deploymentHosts = deploymentHostsFor inventory;
  deploymentHostNames = sortedAttrNames deploymentHosts;
  realizationNodes = realizationNodesFor inventory;
in
if
  renderHostConfig ? deploymentHost
  && builtins.isString renderHostConfig.deploymentHost
    && builtins.hasAttr renderHostConfig.deploymentHost deploymentHosts
then
  renderHostConfig.deploymentHost
else if
  builtins.hasAttr hostname realizationNodes
  && builtins.isAttrs realizationNodes.${hostname}
  && realizationNodes.${hostname} ? host
  && builtins.isString realizationNodes.${hostname}.host
    && builtins.hasAttr realizationNodes.${hostname}.host deploymentHosts
then
  realizationNodes.${hostname}.host
else if builtins.hasAttr hostname deploymentHosts then
  hostname
else if builtins.length deploymentHostNames == 1 then
  builtins.head deploymentHostNames
else
  throw ''
    ${file}: could not resolve deployment host for '${hostname}'

    known deployment hosts:
    ${builtins.concatStringsSep "\n  - " ([ "" ] ++ deploymentHostNames)}
  ''
