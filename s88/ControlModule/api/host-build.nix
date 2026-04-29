{
  lib,
  selectors,
  builders,
  renderHostNetwork,
  renderDryConfig,
  currentSystem ? if builtins ? currentSystem then builtins.currentSystem else "x86_64-linux",
}:

let
  buildInputs = import ../lookup/host-build-inputs.nix {
    inherit selectors;
  };

  sortedAttrNames = attrs: lib.sort builtins.lessThan (builtins.attrNames attrs);

  disabledSelectionFrom =
    disabled:
    let
      disabledNames = sortedAttrNames disabled;

      _validateDisabledValues = builtins.foldl' (
        acc: name:
        let
          value = disabled.${name};
        in
        if builtins.isBool value then
          acc
        else
          throw ''
            s88/ControlModule/api/host-build.nix: disabled entry '${name}' must be a boolean

            value:
            ${builtins.toJSON value}
          ''
      ) true disabledNames;
    in
    builtins.seq _validateDisabledValues (
      builtins.listToAttrs (
        map (name: {
          inherit name;
          value = false;
        }) (lib.filter (name: disabled.${name}) disabledNames)
      )
    );

  inherit (import ./container-defaults.nix { inherit lib; }) mergeContainerDefaults;

  buildHost =
    {
      selector ? null,
      hostname ? null,
      intent ? null,
      inventory ? null,
      intentPath ? null,
      inventoryPath ? null,
      system ? currentSystem,
      containerDefaults ? { },
      disabled ? { },
      containerSelection ? disabledSelectionFrom disabled,
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
        hostName = resolved.selectorValue;
        hostContext = resolved.hostContext;
        cpm = controlPlaneOut;
        inventory = resolved.globalInventory;
      };

      selectedContainers = import ./container-selection.nix {
        inherit
          lib
          containerSelection
          ;
        containers = renderedHost.containers or { };
      };

      renderedHostWithSelectedContainers = renderedHost // {
        containers = builtins.mapAttrs (
          _: container: mergeContainerDefaults containerDefaults container
        ) selectedContainers;
      };
    in
    {
      inherit
        compilerOut
        forwardingOut
        controlPlaneOut
        ;

      renderedHost = renderedHostWithSelectedContainers;

      fabricInputs = resolved.fabricInputs;
      globalInventory = resolved.globalInventory;
      hostContext = resolved.hostContext;

      selectedUnits = renderedHostWithSelectedContainers.selectedUnits or [ ];
      selectedRoleNames = renderedHostWithSelectedContainers.selectedRoleNames or [ ];
      selectedRoles = renderedHostWithSelectedContainers.selectedRoles or { };
      containers = renderedHostWithSelectedContainers.containers or { };
    };

  buildHostFromPaths =
    {
      intentPath,
      inventoryPath,
      selector ? null,
      hostname ? null,
      system ? currentSystem,
      containerDefaults ? { },
      disabled ? { },
      containerSelection ? disabledSelectionFrom disabled,
      file ? "s88/CM/network/api/host-build.nix",
    }:
    buildHost {
      inherit
        intentPath
        inventoryPath
        selector
        hostname
        system
        containerDefaults
        disabled
        containerSelection
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
