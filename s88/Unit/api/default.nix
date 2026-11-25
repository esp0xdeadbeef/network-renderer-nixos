{
  lib,
  repoRoot ? ../../..,
  flakeInputs ? { },
}:

let
  selectors = import ../../ControlModule/lookup/host-query.nix { inherit lib; };
  realizationPorts = import ../physical/realization-ports.nix { inherit lib; };

  realizationModel = flakeInputs.network-realization-model or null;

  canonicalFromCpm =
    cpm:
    if realizationModel == null then
      { }
    else
      (realizationModel.lib.realizeFromCpm {
        inherit cpm;
        requestScope = {
          kind = "complete-artifact";
          identity = "network-renderer-nixos";
        };
        rootLockIdentity = "network-renderer-nixos-flake-lock";
        producerRevision = realizationModel.rev or "unknown";
      }).canonical or { };

  renderHostNetworkImpl =
    {
      hostName,
      hostContext ? null,
      cpm,
      source ? { },

      canonicalCollections ? { },
    }:
    import ../render/host-network.nix {
      repoPath = repoRoot;
      inherit
        lib
        hostName
        hostContext
        cpm
        source
        canonicalCollections
        ;
    };

  renderDryConfigImpl =
    {
      cpm ? null,
      cpmPath ? null,
      source ? { },
      exampleDir ? null,
      debug ? false,
    }:
    import ../render/dry-config-output.nix {
      repoRoot = builtins.toString repoRoot;
      inherit lib;
      renderer = {
        loadControlPlane = selectors.loadStructuredPath;
        renderHostNetwork = renderHostNetworkImpl;
      };
      inherit
        cpm
        cpmPath
        source
        exampleDir
        debug
        canonicalFromCpm
        ;
    };

  hostBuilders = import ./host-build.nix {
    repoPath = repoRoot;
    inherit
      lib
      selectors
      canonicalFromCpm
      ;
    renderHostNetwork = renderHostNetworkImpl;
  };

  dryRenderBuild = import ./dry-render-build.nix {
    inherit
      selectors
      ;
    renderDryConfig = renderDryConfigImpl;
  };

  hostBuild = import ./module-host-build.nix {
    inherit
      lib
      selectors
      ;
    buildHostFromControlPlane = hostBuilders.buildHostFromControlPlane;
  };

  host = import ./host/default.nix {
    repoPath = repoRoot;
    inherit
      lib
      selectors
      ;
    buildHostFromControlPlane = hostBuilders.buildHostFromControlPlane;
  };

  bridges = import ./bridges/default.nix {
    repoPath = repoRoot;
    inherit
      lib
      selectors
      ;
    buildHostFromControlPlane = hostBuilders.buildHostFromControlPlane;
  };

  containers = import ./containers/default.nix {
    repoPath = repoRoot;
    inherit
      lib
      selectors
      ;
    buildHostFromControlPlane = hostBuilders.buildHostFromControlPlane;
  };

in
{
  inherit
    realizationPorts
    selectors
    flakeInputs
    hostBuild
    host
    bridges
    containers
    canonicalFromCpm
    ;

  renderer = {
    inherit canonicalFromCpm;

    loadControlPlane = selectors.loadStructuredPath;

    inherit (hostBuilders)
      buildHostFromControlPlane
      ;

    hostModule = args: (hostBuild args).nixosModule;

    renderHostNetwork = renderHostNetworkImpl;
    renderDryConfig = renderDryConfigImpl;
  };
}
