{ lib
, repoPath
, selectors
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

  # NOTE: buildHost uses only pre-built CPM output. Per FS-310-HDS-010-SDS-010-SMS-100,
  # renderers must consume ONLY CPM output. The fallback that ran compiler->NFM->CPM
  # internally when controlPlaneOut was null has been removed (CMC-NIXOS-REMOVE-INTENT-V2).
  # Pipeline orchestration belongs in the nixos host repo, not the renderer.
  buildHost =
    { selector ? null
    , hostname ? null
    , intent ? null
    , inventory ? null
    , controlPlaneOut ? null
    , compilerOut ? { }
    , forwardingOut ? { }
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
          file
          ;
      };

      # CMC-NIXOS-REMOVE-INTENT-V2: controlPlaneOut is REQUIRED.
      # The renderer no longer runs compiler->NFM->CPM internally.
      # Pipeline orchestration belongs in the host repo.
      resolvedControlPlaneOut =
        if controlPlaneOut != null then
          controlPlaneOut
        else
          throw ''
            s88/Unit/api/host-build.nix: 'controlPlaneOut' (pre-built CPM output) is required.
            Per FS-310-HDS-010-SDS-010-SMS-100, renderers consume ONLY CPM output.
            The pipeline (compiler -> NFM -> CPM) must run in the host repo, not inside the renderer.
          '';

      runtimeTargets =
        trace.emit "host-build:${resolved.selectorValue}:flatten-runtime-targets" (
          flattenRuntimeTargets resolvedControlPlaneOut
        );

      renderedHost = trace.emit "host-build:${resolved.selectorValue}:render-host-network" (renderHostNetwork {
        hostName = resolved.selectorValue;
        hostContext = resolved.hostContext;
        cpm = resolvedControlPlaneOut;
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
        inherit compilerOut forwardingOut;
        controlPlaneOut = resolvedControlPlaneOut;
        renderedHostNetwork = renderedHostWithSelectedContainers;
      };
    in
    {
      inherit
        debugPayload
        ;
      inherit compilerOut forwardingOut;
      controlPlaneOut = resolvedControlPlaneOut;

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

  # CMC-NIXOS-REMOVE-INTENT-V2: buildHostFromControlPlane is the primary entry point.
  # It accepts pre-built CPM output and skips internal pipeline compilation.
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

in
{
  inherit
    buildHost
    buildHostFromControlPlane
    ;
}
