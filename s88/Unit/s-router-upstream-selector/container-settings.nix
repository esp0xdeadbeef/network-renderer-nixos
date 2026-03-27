{
  config,
  lib,
  controlPlaneOut,
  forwardingOut,
  globalInventory,
  ...
}:

let
  hostname = config.networking.hostName;
  inventory = globalInventory;

  sortedAttrNames = attrs: lib.sort builtins.lessThan (builtins.attrNames attrs);

  renderHosts =
    if inventory ? render
      && builtins.isAttrs inventory.render
      && inventory.render ? hosts
      && builtins.isAttrs inventory.render.hosts
    then
      inventory.render.hosts
    else
      { };

  renderHostConfig =
    if builtins.hasAttr hostname renderHosts && builtins.isAttrs renderHosts.${hostname} then
      renderHosts.${hostname}
    else
      { };

  deploymentHosts =
    if inventory ? deployment
      && builtins.isAttrs inventory.deployment
      && inventory.deployment ? hosts
      && builtins.isAttrs inventory.deployment.hosts
    then
      inventory.deployment.hosts
    else
      { };

  deploymentHostNames = sortedAttrNames deploymentHosts;

  realizationNodes =
    if inventory ? realization
      && builtins.isAttrs inventory.realization
      && inventory.realization ? nodes
      && builtins.isAttrs inventory.realization.nodes
    then
      inventory.realization.nodes
    else
      { };

  deploymentHostName =
    if renderHostConfig ? deploymentHost
      && builtins.isString renderHostConfig.deploymentHost
      && builtins.hasAttr renderHostConfig.deploymentHost deploymentHosts
    then
      renderHostConfig.deploymentHost
    else if builtins.hasAttr hostname realizationNodes
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
        container-settings.nix: could not resolve deployment host for '${hostname}'

        known deployment hosts:
        ${builtins.concatStringsSep "\n  - " ([ "" ] ++ deploymentHostNames)}
      '';

  cpmData =
    if controlPlaneOut ? control_plane_model
      && builtins.isAttrs controlPlaneOut.control_plane_model
      && controlPlaneOut.control_plane_model ? data
      && builtins.isAttrs controlPlaneOut.control_plane_model.data
    then
      controlPlaneOut.control_plane_model.data
    else
      { };

  siteTreeForEnterprise =
    enterprise:
      if enterprise ? site && builtins.isAttrs enterprise.site then
        enterprise.site
      else if builtins.isAttrs enterprise then
        enterprise
      else
        { };

  siteEntries =
    lib.concatMap (
      enterpriseName:
      let
        siteTree = siteTreeForEnterprise cpmData.${enterpriseName};
      in
      map
        (
          siteName:
          {
            inherit enterpriseName siteName;
            site = siteTree.${siteName};
          }
        )
        (sortedAttrNames siteTree)
    ) (sortedAttrNames cpmData);

  runtimeTargets =
    lib.foldl' (
      acc: entry:
      acc
      // (
        if entry.site ? runtimeTargets && builtins.isAttrs entry.site.runtimeTargets then
          entry.site.runtimeTargets
        else
          { }
      )
    ) { } siteEntries;

  runtimeTargetNames = sortedAttrNames runtimeTargets;

  logicalNodeNameForUnit =
    unitName:
      if builtins.hasAttr unitName runtimeTargets
        && runtimeTargets.${unitName} ? logicalNode
        && builtins.isAttrs runtimeTargets.${unitName}.logicalNode
        && runtimeTargets.${unitName}.logicalNode ? name
        && builtins.isString runtimeTargets.${unitName}.logicalNode.name
      then
        runtimeTargets.${unitName}.logicalNode.name
      else
        null;

  placementHostForUnit =
    unitName:
      if builtins.hasAttr unitName runtimeTargets
        && runtimeTargets.${unitName} ? placement
        && builtins.isAttrs runtimeTargets.${unitName}.placement
        && runtimeTargets.${unitName}.placement ? host
        && builtins.isString runtimeTargets.${unitName}.placement.host
      then
        runtimeTargets.${unitName}.placement.host
      else
        null;

  realizationHostForUnit =
    unitName:
      if builtins.hasAttr unitName realizationNodes
        && builtins.isAttrs realizationNodes.${unitName}
        && realizationNodes.${unitName} ? host
        && builtins.isString realizationNodes.${unitName}.host
      then
        realizationNodes.${unitName}.host
      else
        null;

  unitRole =
    unitName:
      if builtins.hasAttr unitName runtimeTargets
        && runtimeTargets.${unitName} ? role
        && builtins.isString runtimeTargets.${unitName}.role
      then
        runtimeTargets.${unitName}.role
      else
        null;

  unitBelongsToHost =
    unitName:
      let
        logicalNodeName = logicalNodeNameForUnit unitName;
      in
      logicalNodeName == hostname
      || unitName == hostname
      || lib.hasPrefix "${hostname}-" unitName
      || placementHostForUnit unitName == deploymentHostName
      || realizationHostForUnit unitName == deploymentHostName;

  selectedUnits =
    lib.filter (
      unitName:
      unitRole unitName == "upstream-selector"
      && unitBelongsToHost unitName
    ) runtimeTargetNames;

  _selectedNonEmpty =
    if selectedUnits != [ ] then
      true
    else
      throw ''
        container-settings.nix: no upstream-selector runtime targets matched this machine

        hostname:
        ${hostname}

        resolved deployment host:
        ${deploymentHostName}

        available runtime targets:
        ${builtins.concatStringsSep "\n  - " ([ "" ] ++ runtimeTargetNames)}
      '';

  collectNodeMatches =
    unitName: value:
      if builtins.isAttrs value then
        let
          direct =
            (lib.optionals (
              value ? nodes
              && builtins.isAttrs value.nodes
              && builtins.hasAttr unitName value.nodes
            ) [
              value.nodes.${unitName}
            ])
            ++ (lib.optionals (
              value ? units
              && builtins.isAttrs value.units
              && builtins.hasAttr unitName value.units
            ) [
              value.units.${unitName}
            ])
            ++ (lib.optionals (
              value ? topology
              && builtins.isAttrs value.topology
              && value.topology ? nodes
              && builtins.isAttrs value.topology.nodes
              && builtins.hasAttr unitName value.topology.nodes
            ) [
              value.topology.nodes.${unitName}
            ])
            ++ (lib.optionals (
              value ? runtimeTargets
              && builtins.isAttrs value.runtimeTargets
              && builtins.hasAttr unitName value.runtimeTargets
            ) [
              value.runtimeTargets.${unitName}
            ])
            ++ (lib.optionals (
              value ? name
              && value.name == unitName
              && value ? ports
              && builtins.isAttrs value.ports
            ) [
              value
            ]);

          nested =
            lib.concatMap
              (name: collectNodeMatches unitName value.${name})
              (sortedAttrNames value);
        in
        direct ++ nested
      else if builtins.isList value then
        lib.concatMap (x: collectNodeMatches unitName x) value
      else
        [ ];

  normalizePorts =
    ports:
      builtins.listToAttrs (
        lib.filter (entry: entry != null) (
          map
            (
              portName:
              let
                port = ports.${portName};
              in
              if builtins.isAttrs port
                && port ? link
                && builtins.isString port.link
              then
                {
                  name = portName;
                  value = {
                    link = port.link;
                  };
                }
              else
                null
            )
            (sortedAttrNames ports)
        )
      );

  forwardingPortsForUnit =
    unitName:
      let
        matches = collectNodeMatches unitName forwardingOut;

        normalizedMatches =
          lib.filter
            (ports: builtins.attrNames ports != [ ])
            (
              map
                (
                  match:
                    if builtins.isAttrs match
                      && match ? ports
                      && builtins.isAttrs match.ports
                    then
                      normalizePorts match.ports
                    else
                      { }
                )
                matches
            );
      in
      if normalizedMatches != [ ] then
        builtins.head normalizedMatches
      else
        { };

  realizationNodeForUnit =
    unitName:
      if builtins.hasAttr unitName realizationNodes then
        realizationNodes.${unitName}
      else
        throw ''
          container-settings.nix: missing realization node for unit '${unitName}'

          known realization nodes:
          ${builtins.concatStringsSep "\n  - " ([ "" ] ++ builtins.attrNames realizationNodes)}
        '';

  realizationPortsForUnit =
    unitName:
      let
        node = realizationNodeForUnit unitName;
      in
      if node ? ports && builtins.isAttrs node.ports then
        node.ports
      else
        throw "container-settings.nix: realization node '${unitName}' is missing ports";

  runtimeTargetForUnit =
    unitName:
      if builtins.hasAttr unitName runtimeTargets then
        runtimeTargets.${unitName}
      else
        let
          matches =
            lib.filter builtins.isAttrs (collectNodeMatches unitName controlPlaneOut);
        in
        if matches != [ ] then
          builtins.head matches
        else
          throw "container-settings.nix: no control-plane runtime target matched unit '${unitName}'";

  fabricSpecForUnit =
    unitName:
      let
        forwardedPorts = forwardingPortsForUnit unitName;
        fallbackPorts = normalizePorts (realizationPortsForUnit unitName);
        selectedPorts =
          if builtins.attrNames forwardedPorts != [ ] then
            forwardedPorts
          else
            fallbackPorts;
      in
      if builtins.attrNames selectedPorts != [ ] then
        {
          ports = selectedPorts;
        }
      else
        throw "container-settings.nix: could not resolve ports for unit '${unitName}' from forwarding model or realization inventory";

  hostBridgeForPort =
    unitName: portName:
      let
        ports = realizationPortsForUnit unitName;
        port =
          if builtins.hasAttr portName ports then
            ports.${portName}
          else
            throw "container-settings.nix: realization port '${portName}' missing for unit '${unitName}'";

        attach =
          if port ? attach && builtins.isAttrs port.attach then
            port.attach
          else
            { };
      in
      if (attach.kind or null) == "bridge"
        && attach ? bridge
        && builtins.isString attach.bridge
      then
        attach.bridge
      else if (attach.kind or null) == "direct"
        && port ? link
        && builtins.isString port.link
      then
        port.link
      else
        throw ''
          container-settings.nix: could not resolve host bridge for unit '${unitName}', port '${portName}'

          port:
          ${builtins.toJSON port}
        '';

  mkContainer =
    unitName:
    let
      fabricSpec = fabricSpecForUnit unitName;
      fabricNodeContext = runtimeTargetForUnit unitName;

      portNames =
        if fabricSpec ? ports && builtins.isAttrs fabricSpec.ports then
          sortedAttrNames fabricSpec.ports
        else
          throw "container-settings.nix: missing ports for unit '${unitName}'";

      extraVeths =
        builtins.listToAttrs (
          map
            (
              portName:
              {
                name = portName;
                value = {
                  hostBridge = hostBridgeForPort unitName portName;
                };
              }
            )
            portNames
        );
    in
    {
      name = unitName;
      value = {
        autoStart = true;

        privateNetwork = true;
        hostBridge = null;

        inherit extraVeths;

        specialArgs = {
          inherit controlPlaneOut fabricSpec fabricNodeContext;
        };

        additionalCapabilities = [
          "CAP_NET_ADMIN"
          "CAP_NET_RAW"
        ];

        config = { controlPlaneOut, fabricSpec, fabricNodeContext, ... }: {
          imports = [
            ./container-upstream-selector
          ];

          _module.args = {
            inherit controlPlaneOut fabricSpec fabricNodeContext;
          };

          networking.hostName = unitName;
        };
      };
    };

  containersGenerated = builtins.listToAttrs (map mkContainer selectedUnits);
in
{
  networking.useNetworkd = true;
  networking.networkmanager.enable = false;
  systemd.network.enable = true;

  containers = containersGenerated;
}
