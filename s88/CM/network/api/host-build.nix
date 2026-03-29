{
  lib,
  selectors,
  builders,
  renderHostNetwork,
  renderDryConfig,
  currentSystem ? builtins.currentSystem,
}:

let
  buildInputs = import ../lookup/host-build-inputs.nix {
    inherit selectors;
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
      file ? "s88/CM/network/api/host-build.nix",
    }:
    let
      resolved = buildInputs.resolveBuildInputs {
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

      compilerOut = builders.buildCompiler {
        intent = resolved.fabricInputs;
        inherit system;
      };

      forwardingOut = builders.buildForwarding {
        inherit compilerOut system;
      };

      controlPlaneOut = builders.buildControlPlane {
        inherit forwardingOut system;
        inventory = resolved.globalInventory;
      };

      renderedHost = renderHostNetwork {
        hostName = resolved.deploymentHostName;
        cpm = controlPlaneOut;
        inventory = resolved.globalInventory;
      };
    in
    {
      inherit
        compilerOut
        forwardingOut
        controlPlaneOut
        renderedHost
        ;

      fabricInputs = resolved.fabricInputs;
      globalInventory = resolved.globalInventory;
      hostContext = resolved.hostContext;

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
      file ? "s88/CM/network/api/host-build.nix",
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
      file ? "s88/CM/network/api/host-build.nix",
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

      compiler = builders.buildCompilerFromPaths {
        inherit intentPath;
      };

      forwarding = builders.buildForwarding {
        compilerOut = compiler;
      };

      controlPlane = builders.buildControlPlane {
        forwardingOut = forwarding;
        inherit inventory;
      };

      rendered = renderDryConfig {
        cpm = controlPlane;
        inherit inventory exampleDir debug;
      };
    in
    if rendered == null then
      throw ''
        s88/CM/network/api/host-build.nix: buildAndRenderFromPaths produced null render output

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
  inherit
    buildHost
    buildHostFromPaths
    buildHostFromOutPath
    buildAndRenderFromPaths
    ;
}
