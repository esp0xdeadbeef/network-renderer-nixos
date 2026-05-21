{ helpers
, resolveDeploymentHostName
,
}:

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

  deploymentHostNameAttempt = builtins.tryEval (resolveDeploymentHostName {
    inherit inventory hostname file;
  });

  deploymentHostName =
    if deploymentHostNameAttempt.success then deploymentHostNameAttempt.value else hostname;
in
rec {
  inherit
    hostname
    renderHosts
    renderHostConfig
    deploymentHosts
    deploymentHostNames
    realizationNodes
    deploymentHostName
    ;

  deploymentHost =
    if builtins.hasAttr deploymentHostName deploymentHosts then
      deploymentHosts.${deploymentHostName}
    else
      { };

  realizationNode =
    if builtins.hasAttr hostname realizationNodes && builtins.isAttrs realizationNodes.${hostname} then
      realizationNodes.${hostname}
    else
      null;
}
