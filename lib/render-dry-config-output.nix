{
  repoRoot,
  cpm ? null,
  cpmPath ? null,
  inventory ? { },
  inventoryPath ? null,
  exampleDir ? null,
  debug ? false,
}:

let
  flake = builtins.getFlake (toString (builtins.toPath repoRoot));

  lib =
    if
      flake ? lib
      && flake.lib ? flakeInputs
      && flake.lib.flakeInputs ? nixpkgs
      && flake.lib.flakeInputs.nixpkgs ? lib
    then
      flake.lib.flakeInputs.nixpkgs.lib
    else
      throw "render-dry-config: unable to resolve nixpkgs lib from flake inputs";

  runtimeContext = import ./runtime-context.nix { inherit lib; };
  cpmAdapter = import ./cpm-runtime-adapter.nix { inherit lib; };

  renderer = flake.lib.renderer;

  sortedAttrNames = attrs: lib.sort builtins.lessThan (builtins.attrNames attrs);

  resolvedCpmPath = if cpmPath == null then null else builtins.toString cpmPath;
  resolvedInventoryPath = if inventoryPath == null then null else builtins.toString inventoryPath;

  resolvedExampleDir =
    if exampleDir != null then
      builtins.toString exampleDir
    else if resolvedCpmPath != null then
      builtins.dirOf resolvedCpmPath
    else
      null;

  controlPlane =
    if cpm != null then
      cpm
    else if resolvedCpmPath != null then
      renderer.loadControlPlane (builtins.toPath resolvedCpmPath)
    else
      throw ''
        render-dry-config: requires either cpm or cpmPath
      '';

  resolvedInventory =
    if inventory != { } then
      inventory
    else if resolvedInventoryPath != null then
      renderer.loadInventory (builtins.toPath resolvedInventoryPath)
    else
      { };

  _validateRuntimeTargets = runtimeContext.validateAllRuntimeTargets {
    cpm = controlPlane;
    inventory = resolvedInventory;
    file = "render-dry-config";
  };

  normalizedRuntimeTargets = cpmAdapter.normalizedRuntimeTargets {
    cpm = controlPlane;
    file = "render-dry-config";
  };

  unitNames = sortedAttrNames normalizedRuntimeTargets;

  deploymentHostNames = lib.sort builtins.lessThan (
    lib.unique (
      map (
        unitName:
        runtimeContext.deploymentHostForUnit {
          cpm = controlPlane;
          inventory = resolvedInventory;
          inherit unitName;
          file = "render-dry-config";
        }
      ) unitNames
    )
  );

  hostRenderings = builtins.listToAttrs (
    map (hostName: {
      name = hostName;
      value = renderer.renderHostNetwork {
        inherit hostName;
        cpm = controlPlane;
        inventory = resolvedInventory;
      };
    }) deploymentHostNames
  );

  hostRenderingsDebug = builtins.mapAttrs (_hostName: hostRendering: {
    hostName = hostRendering.hostName or null;
    deploymentHostName = hostRendering.deploymentHostName or null;
    runtimeRole = hostRendering.runtimeRole or null;
    selectedUnits = hostRendering.selectedUnits or [ ];
    selectedRoleNames = hostRendering.selectedRoleNames or [ ];
    bridgeNameMap = hostRendering.bridgeNameMap or { };
    bridges = hostRendering.bridges or { };
    netdevs = hostRendering.netdevs or { };
    networks = hostRendering.networks or { };
    attachTargets = hostRendering.attachTargets or [ ];
    localAttachTargets = hostRendering.localAttachTargets or [ ];
    uplinks = hostRendering.uplinks or { };
    transitBridges = hostRendering.transitBridges or { };
    containers = builtins.listToAttrs (
      map (containerName: {
        name = containerName;
        value =
          let
            container = hostRendering.containers.${containerName};
          in
          {
            autoStart = container.autoStart or false;
            privateNetwork = container.privateNetwork or false;
            extraVeths = container.extraVeths or { };
            bindMounts = container.bindMounts or { };
            allowedDevices = container.allowedDevices or [ ];
            additionalCapabilities = container.additionalCapabilities or [ ];
            specialArgs = {
              unitName =
                if container ? specialArgs && container.specialArgs ? unitName then
                  container.specialArgs.unitName
                else
                  containerName;
              deploymentHostName =
                if container ? specialArgs && container.specialArgs ? deploymentHostName then
                  container.specialArgs.deploymentHostName
                else
                  null;
              s88RoleName =
                if container ? specialArgs && container.specialArgs ? s88RoleName then
                  container.specialArgs.s88RoleName
                else
                  null;
            };
          };
      }) (sortedAttrNames (hostRendering.containers or { }))
    );
    debug = hostRendering.debug or { };
  }) hostRenderings;

  renderedInterfacesForUnit =
    unitName:
    let
      deploymentHostName = runtimeContext.deploymentHostForUnit {
        cpm = controlPlane;
        inventory = resolvedInventory;
        inherit unitName;
        file = "render-dry-config";
      };

      hostRendering =
        if builtins.hasAttr deploymentHostName hostRenderings then
          hostRenderings.${deploymentHostName}
        else
          throw ''
            render-dry-config: unit '${unitName}' references unknown deployment host '${deploymentHostName}'
          '';

      bridgeNameMap = hostRendering.bridgeNameMap;
      interfaces = normalizedRuntimeTargets.${unitName}.interfaces or { };
    in
    builtins.listToAttrs (
      map (
        ifName:
        let
          iface = interfaces.${ifName};

          renderedHostBridgeName =
            if builtins.hasAttr iface.hostBridge bridgeNameMap then
              bridgeNameMap.${iface.hostBridge}
            else
              throw ''
                render-dry-config: missing rendered bridge for '${iface.hostBridge}' (unit '${unitName}', interface '${ifName}')
              '';
        in
        {
          name = ifName;
          value = iface // {
            inherit renderedHostBridgeName;
          };
        }
      ) (sortedAttrNames interfaces)
    );

  renderHosts = builtins.listToAttrs (
    map (
      hostName:
      let
        hostRendering = hostRenderings.${hostName};
      in
      {
        name = hostName;
        value = {
          network = {
            bridges = hostRendering.bridges;
            netdevs = hostRendering.netdevs;
            networks = hostRendering.networks;
          };
        };
      }
    ) deploymentHostNames
  );

  renderNodes = builtins.listToAttrs (
    map (unitName: {
      name = unitName;
      value = {
        logicalNode = runtimeContext.logicalNodeForUnit {
          cpm = controlPlane;
          inventory = resolvedInventory;
          inherit unitName;
          file = "render-dry-config";
        };

        deploymentHostName = runtimeContext.deploymentHostForUnit {
          cpm = controlPlane;
          inventory = resolvedInventory;
          inherit unitName;
          file = "render-dry-config";
        };

        role = runtimeContext.roleForUnit {
          cpm = controlPlane;
          inventory = resolvedInventory;
          inherit unitName;
          file = "render-dry-config";
        };

        interfaces = renderedInterfacesForUnit unitName;
        loopback = normalizedRuntimeTargets.${unitName}.loopback or { };
      };
    }) unitNames
  );

  output = {
    metadata = {
      sourcePaths = {
        repoRoot = builtins.toString repoRoot;
        cpmPath = resolvedCpmPath;
        inventoryPath = resolvedInventoryPath;
        exampleDir = resolvedExampleDir;
      };
    };

    render = {
      hosts = renderHosts;
      nodes = renderNodes;
    };
  }
  // (
    if debug then
      {
        debug = {
          controlPlane = controlPlane;
          inventory = resolvedInventory;
          normalizedRuntimeTargets = normalizedRuntimeTargets;
          hostRenderings = hostRenderingsDebug;
        };
      }
    else
      { }
  );

  validation = builtins.seq _validateRuntimeTargets (
    if unitNames == [ ] then
      throw ''
        render-dry-config: no runtime targets found in control-plane model
      ''
    else if deploymentHostNames == [ ] then
      throw ''
        render-dry-config: no deployment hosts found in control-plane model
      ''
    else if output.render.hosts == { } && output.render.nodes == { } then
      throw ''
        render-dry-config: empty render output
      ''
    else
      true
  );
in
builtins.seq validation output
