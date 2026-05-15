{
  lib,
  selectors,
  builders,
  renderHostNetwork,
  currentSystem ? if builtins ? currentSystem then builtins.currentSystem else "x86_64-linux",
}:

let
  buildInputs = import ../../ControlModule/lookup/host-build-inputs.nix {
    inherit selectors;
  };

  hostSelection = import ./host-selection.nix { inherit lib; };

  inherit (hostSelection) disabledSelectionFrom;

  inherit (import ../../ControlModule/api/container-defaults.nix { inherit lib; }) mergeContainerDefaults;

  flattenRuntimeTargets = controlPlaneOut:
    let
      controlPlaneData = ((controlPlaneOut.control_plane_model or { }).data or { });
    in
    builtins.listToAttrs (
      builtins.concatLists (
        builtins.map
          (enterpriseName:
            let enterprise = controlPlaneData.${enterpriseName};
            in
            builtins.concatLists (
              builtins.map
                (siteName:
                  let
                    site = enterprise.${siteName};
                    runtimeTargets = site.runtimeTargets or { };
                  in
                  builtins.map
                    (targetName: {
                      name = "${enterpriseName}.${siteName}.${targetName}";
                      value = runtimeTargets.${targetName};
                    })
                    (builtins.attrNames runtimeTargets))
                (builtins.attrNames enterprise)
            ))
          (builtins.attrNames controlPlaneData)
      )
    );

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
      file ? "s88/Unit/api/host-build.nix",
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

      runtimeTargets = flattenRuntimeTargets controlPlaneOut;

      renderedHost = renderHostNetwork {
        hostName = resolved.selectorValue;
        hostContext = resolved.hostContext;
        cpm = controlPlaneOut;
        inventory = resolved.globalInventory;
      };

      renderedHostWithSelectedContainers = hostSelection.selectedContainersForHost {
        inherit
          containerDefaults
          containerSelection
          renderedHost
          mergeContainerDefaults
          ;
      };

      debugPayload = import ../../ControlModule/api/debug-payload.nix {
        inherit
          lib
          system
          ;
        hostName = resolved.selectorValue;
        hostContext = resolved.hostContext;
        intent = resolved.fabricInputs;
        globalInventory = resolved.globalInventory;
        inherit
          compilerOut
          forwardingOut
          controlPlaneOut
          ;
        renderedHostNetwork = renderedHostWithSelectedContainers;
        inherit intentPath inventoryPath;
      };
    in
    {
      inherit
        compilerOut
        forwardingOut
        controlPlaneOut
        debugPayload
        ;

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
    {
      intentPath,
      inventoryPath,
      selector ? null,
      hostname ? null,
      system ? currentSystem,
      containerDefaults ? { },
      disabled ? { },
      containerSelection ? disabledSelectionFrom disabled,
      file ? "s88/Unit/api/host-build.nix",
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
      file ? "s88/Unit/api/host-build.nix",
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
    buildHostFromOutPath
    ;
}
