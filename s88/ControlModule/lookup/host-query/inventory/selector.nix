{ lib
, helpers
,
}:

{ selector
, intent
, source
, file ? "s88/ControlModule/lookup/host-query.nix"
,
}:

let
  inherit (helpers)
    deploymentHostsFor
    hostNamesFromNodes
    isNonEmptyAttrs
    matchingNodesBy
    realizationNodesFor
    renderHostsFor
    selectAttrs
    sortedAttrNames
    ;

  _selectorIsString =
    if builtins.isString selector then true else throw "${file}: selector must be a string";

  realizationNodes = realizationNodesFor source;
  deploymentHosts = deploymentHostsFor source;
  renderHosts = renderHostsFor source;

  exactRealizationNode =
    if builtins.hasAttr selector realizationNodes then realizationNodes.${selector} else null;

  exactDeploymentHost =
    if builtins.hasAttr selector deploymentHosts then deploymentHosts.${selector} else null;

  exactRenderHost =
    if builtins.hasAttr selector renderHosts && builtins.isAttrs renderHosts.${selector} then
      renderHosts.${selector}
    else
      null;

  renderHostDeploymentHostName =
    if exactRenderHost == null then
      null
    else if exactRenderHost ? deploymentHost && exactRenderHost.deploymentHost != null then
      if
        builtins.isString exactRenderHost.deploymentHost
        && builtins.hasAttr exactRenderHost.deploymentHost deploymentHosts
      then
        exactRenderHost.deploymentHost
      else
        throw ''
          ${file}: render host '${selector}' references unknown deployment host '${builtins.toJSON exactRenderHost.deploymentHost}'

          known deployment hosts:
          ${builtins.concatStringsSep "\n  - " ([ "" ] ++ (sortedAttrNames deploymentHosts))}
        ''
    else if builtins.hasAttr selector deploymentHosts then
      selector
    else if builtins.length (sortedAttrNames deploymentHosts) == 1 then
      builtins.head (sortedAttrNames deploymentHosts)
    else
      null;

  matchingSiteNodes = matchingNodesBy source (
    _: node:
      node ? logicalNode
      && builtins.isAttrs node.logicalNode
      && (node.logicalNode.site or null) == selector
  );

  matchingLogicalNameNodes = matchingNodesBy source (
    _: node:
      node ? logicalNode
      && builtins.isAttrs node.logicalNode
      && (node.logicalNode.name or null) == selector
  );

  nodesOnDeploymentHost =
    if exactDeploymentHost != null then
      matchingNodesBy source (_: node: (node.host or null) == selector)
    else
      { };

  selectedRealizationNodes =
    if exactRealizationNode != null then
      { "${selector}" = exactRealizationNode; }
    else if exactDeploymentHost != null then
      nodesOnDeploymentHost
    else if isNonEmptyAttrs matchingSiteNodes then
      matchingSiteNodes
    else if isNonEmptyAttrs matchingLogicalNameNodes then
      matchingLogicalNameNodes
    else
      { };

  selectedDeploymentHostNames =
    if exactDeploymentHost != null then
      [ selector ]
    else if exactRealizationNode != null then
      hostNamesFromNodes selectedRealizationNodes
    else if exactRenderHost != null then
      lib.optionals (renderHostDeploymentHostName != null) [ renderHostDeploymentHostName ]
    else if isNonEmptyAttrs selectedRealizationNodes then
      hostNamesFromNodes selectedRealizationNodes
    else if builtins.hasAttr selector deploymentHosts then
      [ selector ]
    else
      [ ];

  selectedDeploymentHosts = selectAttrs selectedDeploymentHostNames deploymentHosts;

  selectedDeploymentHostName =
    if builtins.length selectedDeploymentHostNames == 1 then
      builtins.head selectedDeploymentHostNames
    else
      null;

  deploymentHost =
    if selectedDeploymentHostName != null && builtins.hasAttr selectedDeploymentHostName deploymentHosts then
      deploymentHosts.${selectedDeploymentHostName}
    else
      { };

  renderHostConfig =
    if exactRenderHost != null then
      exactRenderHost
    else if selectedDeploymentHostName != null && builtins.hasAttr selectedDeploymentHostName renderHosts then
      renderHosts.${selectedDeploymentHostName}
    else if builtins.hasAttr selector renderHosts then
      renderHosts.${selector}
    else
      { };

  logicalValues =
    field:
    lib.filter (value: value != null) (
      lib.unique (
        map
          (
            nodeName:
            let
              logicalNode = selectedRealizationNodes.${nodeName}.logicalNode or { };
            in
              logicalNode.${field} or null
          )
          (sortedAttrNames selectedRealizationNodes)
      )
    );

  selectorType =
    if exactRealizationNode != null then
      "realization-node"
    else if exactDeploymentHost != null then
      "deployment-host"
    else if exactRenderHost != null then
      "render-host"
    else if isNonEmptyAttrs matchingSiteNodes then
      "site"
    else if isNonEmptyAttrs matchingLogicalNameNodes then
      "logical-node"
    else
      "unknown";
in
{
  inherit
    selector
    selectorType
    deploymentHost
    renderHostConfig
    renderHosts
    ;

  hostname = selector;
  deploymentHostName = selectedDeploymentHostName;
  deploymentHostNames = selectedDeploymentHostNames;
  deploymentHosts = selectedDeploymentHosts;
  matchedSites = logicalValues "site";
  matchedEnterprises = logicalValues "enterprise";
  matchedLogicalNodes = logicalValues "name";
  realizationNode = exactRealizationNode;
  realizationNodes = selectedRealizationNodes;
}
