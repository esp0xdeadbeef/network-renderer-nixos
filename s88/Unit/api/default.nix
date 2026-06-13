{ lib
, repoRoot ? ../../..
, flakeInputs ? { }
,
}:

let
  selectors = import ../../ControlModule/lookup/host-query.nix { inherit lib; };
  realizationPorts = import ../physical/realization-ports.nix { inherit lib; };

  # CMC-NIXOS-REMOVE-INTENT-V2: builders removed — pipeline orchestration
  # (compiler→NFM→CPM) belongs in the host repo, not the renderer.
  # Per FS-310-HDS-010-SDS-010-SMS-100, renderers consume ONLY CPM output.

  renderHostNetworkImpl =
    { hostName
    , hostContext ? null
    , cpm
    , source ? { }
    ,
    }:
    import ../render/host-network.nix {
      repoPath = repoRoot;
      inherit
        lib
        hostName
        hostContext
        cpm
        source
        ;
    };

  renderDryConfigImpl =
    { cpm ? null
    , cpmPath ? null
    , source ? { }
    , exampleDir ? null
    , debug ? false
    ,
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
        ;
    };

  hostBuilders = import ./host-build.nix {
    repoPath = repoRoot;
    inherit
      lib
      selectors
      ;
    renderHostNetwork = renderHostNetworkImpl;
  };

  # NOTE: dryRenderBuild no longer provides buildAndRenderFromPaths.
  # Per SMS-100, the renderer must NOT run compiler→NFM→CPM from file paths.
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
    ;

  renderer = {
    # CMC-NIXOS-REMOVE-INTENT-V2: loadIntent/loadInventory removed.
    # Renderers must not provide generic file loaders that could load
    # upstream intent.nix/inventory.nix from disk (SMS-100).
    loadControlPlane = selectors.loadStructuredPath;

    # CMC-NIXOS-REMOVE-INTENT-V2: Pipeline builders (buildCompiler,
    # buildForwarding, buildControlPlane) removed. Pipeline orchestration
    # belongs in the nixos host repo, not inside the renderer.
    # Renderers consume pre-built CPM output via buildHostFromControlPlane.

    # NOTE: buildHostFromPaths and buildHostFromOutPath removed.
    # Use buildHostFromControlPlane with pre-built CPM output.
    inherit (hostBuilders)
      buildHostFromControlPlane
      ;

    hostModule = args: (hostBuild args).nixosModule;

    # NOTE: buildAndRenderFromPaths removed — renderer no longer runs pipeline from paths.
    # Use renderDryConfig with pre-built CPM output instead.

    renderHostNetwork = renderHostNetworkImpl;
    renderDryConfig = renderDryConfigImpl;
  };
}
