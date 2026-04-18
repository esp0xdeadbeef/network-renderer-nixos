{ lib }:

let
  sortedAttrNames = attrs: lib.sort builtins.lessThan (builtins.attrNames attrs);

  isNonEmptyAttrs = value: builtins.isAttrs value && sortedAttrNames value != [ ];

  realizationNodesFor =
    inventory:
    if
      inventory ? realization
      && builtins.isAttrs inventory.realization
      && inventory.realization ? nodes
      && builtins.isAttrs inventory.realization.nodes
    then
      inventory.realization.nodes
    else
      { };

  deploymentHostsFor =
    inventory:
    if
      inventory ? deployment
      && builtins.isAttrs inventory.deployment
      && inventory.deployment ? hosts
      && builtins.isAttrs inventory.deployment.hosts
    then
      inventory.deployment.hosts
    else
      { };

  renderHostsFor =
    inventory:
    if
      inventory ? render
      && builtins.isAttrs inventory.render
      && inventory.render ? hosts
      && builtins.isAttrs inventory.render.hosts
    then
      inventory.render.hosts
    else
      { };

  selectAttrs =
    names: attrs:
    builtins.listToAttrs (
      map (name: {
        inherit name;
        value = attrs.${name};
      }) (lib.filter (name: builtins.hasAttr name attrs) names)
    );

  matchingNodesBy =
    inventory: predicate:
    let
      realizationNodes = realizationNodesFor inventory;
    in
    builtins.listToAttrs (
      map
        (nodeName: {
          name = nodeName;
          value = realizationNodes.${nodeName};
        })
        (
          lib.filter (nodeName: predicate nodeName realizationNodes.${nodeName}) (
            sortedAttrNames realizationNodes
          )
        )
    );

  hostNamesFromNodes =
    nodes:
    lib.unique (
      lib.filter builtins.isString (
        map (
          nodeName:
          let
            node = nodes.${nodeName};
          in
          if node ? host && builtins.isString node.host then node.host else null
        ) (sortedAttrNames nodes)
      )
    );

  resolveDeploymentHostName =
    {
      inventory,
      hostname,
      file ? "s88/ControlModule/lookup/host-query.nix",
    }:
    let
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
      '';

  hostContextForSelector =
    {
      selector,
      intent,
      inventory,
      file ? "s88/ControlModule/lookup/host-query.nix",
    }:
    let
      _selectorIsString =
        if builtins.isString selector then true else throw "${file}: selector must be a string";

      realizationNodes = realizationNodesFor inventory;
      deploymentHosts = deploymentHostsFor inventory;
      renderHosts = renderHostsFor inventory;

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

      matchingSiteNodes = matchingNodesBy inventory (
        _: node:
        node ? logicalNode
        && builtins.isAttrs node.logicalNode
        && (node.logicalNode.site or null) == selector
      );

      matchingLogicalNameNodes = matchingNodesBy inventory (
        _: node:
        node ? logicalNode
        && builtins.isAttrs node.logicalNode
        && (node.logicalNode.name or null) == selector
      );

      nodesOnDeploymentHost =
        if exactDeploymentHost != null then
          matchingNodesBy inventory (_: node: (node.host or null) == selector)
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
        if
          selectedDeploymentHostName != null && builtins.hasAttr selectedDeploymentHostName deploymentHosts
        then
          deploymentHosts.${selectedDeploymentHostName}
        else
          { };

      renderHostConfig =
        if exactRenderHost != null then
          exactRenderHost
        else if
          selectedDeploymentHostName != null && builtins.hasAttr selectedDeploymentHostName renderHosts
        then
          renderHosts.${selectedDeploymentHostName}
        else if builtins.hasAttr selector renderHosts then
          renderHosts.${selector}
        else
          { };

      matchedSites = lib.filter (value: value != null) (
        lib.unique (
          map (
            nodeName:
            let
              logicalNode = selectedRealizationNodes.${nodeName}.logicalNode or { };
            in
            logicalNode.site or null
          ) (sortedAttrNames selectedRealizationNodes)
        )
      );

      matchedEnterprises = lib.filter (value: value != null) (
        lib.unique (
          map (
            nodeName:
            let
              logicalNode = selectedRealizationNodes.${nodeName}.logicalNode or { };
            in
            logicalNode.enterprise or null
          ) (sortedAttrNames selectedRealizationNodes)
        )
      );

      matchedLogicalNodes = lib.filter (value: value != null) (
        lib.unique (
          map (
            nodeName:
            let
              logicalNode = selectedRealizationNodes.${nodeName}.logicalNode or { };
            in
            logicalNode.name or null
          ) (sortedAttrNames selectedRealizationNodes)
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
      matchedSites = matchedSites;
      matchedEnterprises = matchedEnterprises;
      matchedLogicalNodes = matchedLogicalNodes;
      realizationNode = exactRealizationNode;
      realizationNodes = selectedRealizationNodes;
    };

  hostContextForHost =
    {
      inventory,
      hostname,
      file ? "s88/ControlModule/lookup/host-query.nix",
    }:
    let
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
    };
in
{
  inherit
    resolveDeploymentHostName
    hostContextForSelector
    hostContextForHost
    ;
}
