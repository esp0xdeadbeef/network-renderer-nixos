{
  lib,
  repoRoot ? ../.,
  flakeInputs ? { },
}:

let
  selectors = import ./host-query.nix { inherit lib; };
  realizationPorts = import ./realization-ports.nix { inherit lib; };

  currentSystem = builtins.currentSystem;

  renderHostNetworkImpl =
    {
      hostName,
      cpm,
      inventory ? { },
    }:
    import ./render-host-network.nix {
      inherit
        lib
        hostName
        cpm
        inventory
        ;
    };

  isControlPlaneLike =
    value:
    builtins.isAttrs value
    && (
      (
        value ? control_plane_model
        && builtins.isAttrs value.control_plane_model
        && value.control_plane_model ? data
        && builtins.isAttrs value.control_plane_model.data
      )
      || (value ? data && builtins.isAttrs value.data)
    );

  resolveSingleDeploymentHostName =
    {
      hostContext,
      selectorValue,
      file ? "lib/api.nix",
    }:
    if hostContext ? deploymentHostName && builtins.isString hostContext.deploymentHostName then
      hostContext.deploymentHostName
    else if
      hostContext ? deploymentHostNames
      && builtins.isList hostContext.deploymentHostNames
      && builtins.length hostContext.deploymentHostNames == 1
    then
      builtins.head hostContext.deploymentHostNames
    else
      throw ''
        ${file}: selector '${selectorValue}' did not resolve to a single deployment host

        deploymentHostNames:
        ${builtins.toJSON (hostContext.deploymentHostNames or [ ])}
      '';

  buildCompiler =
    {
      intent,
      system ? currentSystem,
    }:
    if
      flakeInputs ? nixos-network-compiler
      && flakeInputs.nixos-network-compiler ? lib
      && flakeInputs.nixos-network-compiler.lib ? compile
    then
      (flakeInputs.nixos-network-compiler.lib.compile system) intent
    else
      throw "lib/api.nix: flake input 'nixos-network-compiler' with lib.compile is required";

  buildForwarding =
    {
      compilerOut,
      system ? currentSystem,
    }:
    if
      flakeInputs ? network-forwarding-model
      && flakeInputs.network-forwarding-model ? lib
      && builtins.hasAttr system flakeInputs.network-forwarding-model.lib
    then
      let
        impl = flakeInputs.network-forwarding-model.lib.${system};
      in
      if builtins.isFunction impl then
        impl { input = compilerOut; }
      else if builtins.isAttrs impl && impl ? build then
        impl.build { input = compilerOut; }
      else
        throw "lib/api.nix: flake input 'network-forwarding-model' has unsupported API shape"
    else if
      flakeInputs ? network-control-plane-model
      && flakeInputs.network-control-plane-model ? lib
      && builtins.hasAttr system flakeInputs.network-control-plane-model.lib
    then
      let
        impl = flakeInputs.network-control-plane-model.lib.${system};
      in
      if builtins.isFunction impl then
        impl { input = compilerOut; }
      else
        throw "lib/api.nix: flake input 'network-control-plane-model' cannot build forwarding output from compiler output"
    else
      throw "lib/api.nix: flake input 'network-forwarding-model' or function-shaped 'network-control-plane-model' is required";

  buildControlPlane =
    {
      forwardingOut,
      inventory,
      system ? currentSystem,
    }:
    if
      flakeInputs ? network-control-plane-model
      && flakeInputs.network-control-plane-model ? lib
      && builtins.hasAttr system flakeInputs.network-control-plane-model.lib
    then
      let
        impl = flakeInputs.network-control-plane-model.lib.${system};
      in
      if builtins.isAttrs impl && impl ? build then
        impl.build {
          input = forwardingOut;
          inherit inventory;
        }
      else if builtins.isFunction impl then
        let
          result = impl { input = forwardingOut; };
        in
        if builtins.isFunction result then result { inherit inventory; } else result
      else if isControlPlaneLike forwardingOut then
        forwardingOut
      else
        throw "lib/api.nix: flake input 'network-control-plane-model' has unsupported API shape"
    else if isControlPlaneLike forwardingOut then
      forwardingOut
    else
      throw "lib/api.nix: flake input 'network-control-plane-model' is required";

  buildCompilerFromPaths =
    {
      intentPath,
      system ? currentSystem,
    }:
    buildCompiler {
      intent = selectors.importMaybeFunction (builtins.toPath intentPath);
      inherit system;
    };

  buildForwardingFromPaths =
    {
      intentPath,
      system ? currentSystem,
    }:
    buildForwarding {
      compilerOut = buildCompilerFromPaths {
        inherit intentPath system;
      };
      inherit system;
    };

  buildControlPlaneFromPaths =
    {
      intentPath,
      inventoryPath,
      system ? currentSystem,
    }:
    buildControlPlane {
      forwardingOut = buildForwardingFromPaths {
        inherit intentPath system;
      };
      inventory = selectors.importMaybeFunction (builtins.toPath inventoryPath);
      inherit system;
    };

  buildHost =
    {
      selector ? null,
      hostname ? null,
      intent ? null,
      inventory ? null,
      intentPath ? null,
      inventoryPath ? null,
      system ? currentSystem,
      file ? "lib/api.nix",
    }:
    let
      queried = selectors.query {
        inherit
          selector
          hostname
          intent
          inventory
          intentPath
          inventoryPath
          file
          ;
      };

      selectorValue =
        if selector != null then
          selector
        else if hostname != null then
          hostname
        else
          "<unknown>";

      deploymentHostName = resolveSingleDeploymentHostName {
        hostContext = queried.hostContext;
        inherit selectorValue file;
      };

      compilerOut = buildCompiler {
        intent = queried.fabricInputs;
        inherit system;
      };

      forwardingOut = buildForwarding {
        inherit compilerOut system;
      };

      controlPlaneOut = buildControlPlane {
        inherit forwardingOut system;
        inventory = queried.globalInventory;
      };

      renderedHost = renderHostNetworkImpl {
        hostName = deploymentHostName;
        cpm = controlPlaneOut;
        inventory = queried.globalInventory;
      };
    in
    {
      inherit
        compilerOut
        forwardingOut
        controlPlaneOut
        renderedHost
        ;

      fabricInputs = queried.fabricInputs;
      globalInventory = queried.globalInventory;
      hostContext = queried.hostContext;

      selectedUnits = renderedHost.selectedUnits or [ ];
      selectedRoleNames = renderedHost.selectedRoleNames or [ ];
      selectedRoles = renderedHost.selectedRoles or { };
      containers = renderedHost.containers or { };
    };

  buildHostFromPaths =
    {
      intentPath,
      inventoryPath,
      selector ? null,
      hostname ? null,
      system ? currentSystem,
      file ? "lib/api.nix",
    }:
    buildHost {
      inherit
        intentPath
        inventoryPath
        selector
        hostname
        system
        file
        ;
    };

  buildHostFromOutPath =
    {
      outPath,
      selector ? null,
      hostname ? null,
      fabricRoot ? null,
      system ? currentSystem,
      file ? "lib/api.nix",
    }:
    let
      paths = selectors.pathsFromOutPath {
        inherit outPath fabricRoot;
      };
    in
    buildHostFromPaths {
      inherit
        selector
        hostname
        system
        file
        ;
      inherit (paths) intentPath inventoryPath;
    };

  buildAndRenderFromPaths =
    {
      intentPath,
      inventoryPath,
      exampleDir ? null,
      debug ? false,
    }:
    let
      inventory = selectors.importMaybeFunction (builtins.toPath inventoryPath);

      compiler = buildCompilerFromPaths {
        inherit intentPath;
      };

      forwarding = buildForwarding {
        compilerOut = compiler;
      };

      controlPlane = buildControlPlane {
        forwardingOut = forwarding;
        inherit inventory;
      };

      rendered = import ./render-dry-config-output.nix {
        repoRoot = builtins.toString repoRoot;
        cpm = controlPlane;
        inherit inventory exampleDir debug;
      };
    in
    if rendered == null then
      throw ''
        lib/api.nix: buildAndRenderFromPaths produced null render output

        intentPath: ${intentPath}
        inventoryPath: ${inventoryPath}
      ''
    else
      {
        inherit compiler forwarding;
        controlPlane = controlPlane;
        render = rendered;
      };
in
{
  inherit realizationPorts selectors flakeInputs;

  renderer = {
    loadIntent = selectors.importMaybeFunction;
    loadInventory = selectors.importMaybeFunction;
    loadControlPlane = selectors.loadStructuredPath;

    inherit
      buildCompiler
      buildForwarding
      buildControlPlane
      buildCompilerFromPaths
      buildForwardingFromPaths
      buildControlPlaneFromPaths
      buildHost
      buildHostFromPaths
      buildHostFromOutPath
      buildAndRenderFromPaths
      ;

    renderHostNetwork = renderHostNetworkImpl;

    renderDryConfig =
      {
        cpmPath,
        inventory ? { },
        inventoryPath ? null,
        exampleDir ? null,
        debug ? false,
      }:
      import ./render-dry-config-output.nix {
        repoRoot = builtins.toString repoRoot;
        inherit
          cpmPath
          inventory
          inventoryPath
          exampleDir
          debug
          ;
      };
  };
}
