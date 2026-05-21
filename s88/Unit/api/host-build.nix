{ lib
, repoPath
, selectors
, builders
, renderHostNetwork
, currentSystem ? if builtins ? currentSystem then builtins.currentSystem else "x86_64-linux"
,
}:

let
  trace = import "${repoPath}/lib/trace.nix" { };

  buildInputs = import ../../ControlModule/lookup/host-build-inputs.nix {
    inherit selectors;
  };

  hostSelection = import ./host-selection.nix { inherit lib; };

  inherit (hostSelection) disabledSelectionFrom;

  inherit (import ../../ControlModule/api/container-defaults.nix { inherit lib; }) mergeContainerDefaults;

  flattenRuntimeTargets = import ./host-build/runtime-targets.nix { };

  buildHost =
    { selector ? null
    , hostname ? null
    , intent ? null
    , inventory ? null
    , intentPath ? null
    , inventoryPath ? null
    , controlPlaneOut ? null
    , compilerOut ? null
    , forwardingOut ? null
    , system ? currentSystem
    , containerDefaults ? { }
    , disabled ? { }
    , containerSelection ? disabledSelectionFrom disabled
    , file ? "s88/Unit/api/host-build.nix"
    ,
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

      compilerOutResolved =
        if compilerOut != null then
          compilerOut
        else if controlPlaneOut != null then
          { }
        else
          trace.emit "host-build:${resolved.selectorValue}:compiler" (builders.buildCompiler {
            intent = resolved.fabricInputs;
            inherit system;
          });

      forwardingOutResolved =
        if forwardingOut != null then
          forwardingOut
        else if controlPlaneOut != null then
          { }
        else
          trace.emit "host-build:${resolved.selectorValue}:forwarding" (builders.buildForwarding {
            compilerOut = compilerOutResolved;
            inherit system;
          });

      controlPlaneOutResolved =
        if controlPlaneOut != null then
          controlPlaneOut
        else
          trace.emit "host-build:${resolved.selectorValue}:control-plane" (builders.buildControlPlane {
            forwardingOut = forwardingOutResolved;
            inherit system;
            inventory = resolved.globalInventory;
          });

      runtimeTargets =
        trace.emit "host-build:${resolved.selectorValue}:flatten-runtime-targets" (
          flattenRuntimeTargets controlPlaneOutResolved
        );

      renderedHost = trace.emit "host-build:${resolved.selectorValue}:render-host-network" (renderHostNetwork {
        hostName = resolved.selectorValue;
        hostContext = resolved.hostContext;
        cpm = controlPlaneOutResolved;
        inventory = resolved.globalInventory;
      });

      renderedHostWithSelectedContainers = trace.emit "host-build:${resolved.selectorValue}:select-containers" (hostSelection.selectedContainersForHost {
        inherit
          containerDefaults
          containerSelection
          renderedHost
          mergeContainerDefaults
          ;
      });

      debugPayload = import ../../ControlModule/api/debug-payload.nix {
        inherit
          lib
          system
          ;
        hostName = resolved.selectorValue;
        hostContext = resolved.hostContext;
        intent = resolved.fabricInputs;
        globalInventory = resolved.globalInventory;
        compilerOut = compilerOutResolved;
        forwardingOut = forwardingOutResolved;
        controlPlaneOut = controlPlaneOutResolved;
        renderedHostNetwork = renderedHostWithSelectedContainers;
        inherit intentPath inventoryPath;
      };
    in
    {
      inherit
        debugPayload
        ;
      compilerOut = compilerOutResolved;
      forwardingOut = forwardingOutResolved;
      controlPlaneOut = controlPlaneOutResolved;

      renderedHost = renderedHostWithSelectedContainers;

      artifactModule = import ../../ControlModule/api/artifact-module.nix { inherit debugPayload; };

      fabricInputs = resolved.fabricInputs;
      globalInventory = resolved.globalInventory;
      hostContext = resolved.hostContext;

      selectedUnits = renderedHostWithSelectedContainers.selectedUnits or [ ];
      selectedRoleNames = renderedHostWithSelectedContainers.selectedRoleNames or [ ];
      selectedRoles = renderedHostWithSelectedContainers.selectedRoles or { };
      containers = renderedHostWithSelectedContainers.containers or { };
      inherit runtimeTargets;
      runtimeTargetNames = builtins.attrNames runtimeTargets;
    };

  buildHostFromPaths =
    { intentPath
    , inventoryPath
    , selector ? null
    , hostname ? null
    , system ? currentSystem
    , containerDefaults ? { }
    , disabled ? { }
    , containerSelection ? disabledSelectionFrom disabled
    , file ? "s88/Unit/api/host-build.nix"
    ,
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

  buildHostFromControlPlane =
    { controlPlaneOut
    , inventory
    , selector ? null
    , hostname ? null
    , system ? currentSystem
    , containerDefaults ? { }
    , disabled ? { }
    , containerSelection ? disabledSelectionFrom disabled
    , file ? "s88/Unit/api/host-build.nix"
    ,
    }:
    buildHost {
      inherit
        inventory
        controlPlaneOut
        selector
        hostname
        system
        containerDefaults
        disabled
        containerSelection
        file
        ;
      intent = { };
    };

  buildHostFromOutPath =
    { outPath
    , selector ? null
    , hostname ? null
    , fabricRoot ? null
    , system ? currentSystem
    , file ? "s88/Unit/api/host-build.nix"
    ,
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

in
{
  inherit
    buildHost
    buildHostFromPaths
    buildHostFromControlPlane
    buildHostFromOutPath
    ;
}
