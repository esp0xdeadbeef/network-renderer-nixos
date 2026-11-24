{
  lib,
  repoPath,
  selectors,
  renderHostNetwork,
  currentSystem ? if builtins ? currentSystem then builtins.currentSystem else "x86_64-linux",

  canonicalCollections ? { },
}:

let
  trace = import "${repoPath}/lib/trace.nix" { };

  buildInputs = import ../../ControlModule/lookup/host-build-inputs.nix {
    inherit selectors;
  };

  hostSelection = import ./host-selection.nix { inherit lib; };

  inherit (hostSelection) disabledSelectionFrom;

  inherit (import ../../ControlModule/api/container-defaults.nix { inherit lib; })
    mergeContainerDefaults
    ;

  flattenRuntimeTargets = import ./host-build/runtime-targets.nix { };

  buildHost =
    {
      selector ? null,
      hostname ? null,
      intent ? null,
      source ? null,
      controlPlaneOut ? null,

      canonicalCollectionsInput ? { },
      compilerOut ? null,
      forwardingOut ? null,
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
          source
          file
          ;
      };

      resolvedControlPlaneOut =
        if controlPlaneOut != null then
          controlPlaneOut
        else
          throw ''
            s88/Unit/api/host-build.nix: 'controlPlaneOut' (pre-built CPM output) is required.
            Per FS-310-HDS-010-SDS-010-SMS-100, renderers consume ONLY CPM output.
            The pipeline (compiler -> NFM -> CPM) must run in the host repo, not inside the renderer.
          '';

      resolvedCompilerOut =
        if compilerOut != null then
          compilerOut
        else if builtins.isAttrs resolvedControlPlaneOut && resolvedControlPlaneOut ? compilerOut then
          resolvedControlPlaneOut.compilerOut
        else
          { };

      resolvedForwardingOut =
        if forwardingOut != null then
          forwardingOut
        else if builtins.isAttrs resolvedControlPlaneOut && resolvedControlPlaneOut ? forwardingOut then
          resolvedControlPlaneOut.forwardingOut
        else
          { };

      effectiveCanonicalCollections =
        if builtins.isAttrs canonicalCollectionsInput then canonicalCollectionsInput else { };

      runtimeTargets = trace.emit "host-build:${resolved.selectorValue}:flatten-runtime-targets" (
        flattenRuntimeTargets resolvedControlPlaneOut effectiveCanonicalCollections
      );

      renderedHost =
        trace.emit "host-build:${resolved.selectorValue}:render-host-network"
          (renderHostNetwork {
            hostName = resolved.selectorValue;
            hostContext = resolved.hostContext;
            cpm = resolvedControlPlaneOut;
            source = resolved.globalInventory;
          });

      renderedHostWithSelectedContainers =
        trace.emit "host-build:${resolved.selectorValue}:select-containers"
          (
            hostSelection.selectedContainersForHost {
              inherit
                containerDefaults
                containerSelection
                renderedHost
                mergeContainerDefaults
                ;
            }
          );

      debugPayload = import ../../ControlModule/api/debug-payload.nix {
        inherit
          lib
          system
          ;
        hostName = resolved.selectorValue;
        hostContext = resolved.hostContext;
        intent = resolved.fabricInputs;
        globalInventory = resolved.globalInventory;
        compilerOut = resolvedCompilerOut;
        forwardingOut = resolvedForwardingOut;
        controlPlaneOut = resolvedControlPlaneOut;
        renderedHostNetwork = renderedHostWithSelectedContainers;
      };
    in
    {
      inherit
        debugPayload
        ;
      compilerOut = resolvedCompilerOut;
      forwardingOut = resolvedForwardingOut;
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

  buildHostFromControlPlane =
    {
      controlPlaneOut,
      selector ? null,
      hostname ? null,
      source ? { },

      canonicalCollectionsInput ? { },
      compilerOut ? null,
      forwardingOut ? null,
      system ? currentSystem,
      containerDefaults ? { },
      disabled ? { },
      containerSelection ? disabledSelectionFrom disabled,
      file ? "s88/Unit/api/host-build.nix",
    }:
    buildHost {
      inherit
        controlPlaneOut
        selector
        hostname
        source
        canonicalCollectionsInput
        compilerOut
        forwardingOut
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
