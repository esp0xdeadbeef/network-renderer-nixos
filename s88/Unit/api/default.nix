{
  lib,
  repoRoot ? ../../..,
  flakeInputs ? { },
}:

let
  selectors = import ../../ControlModule/lookup/host-query.nix { inherit lib; };
  realizationPorts = import ../physical/realization-ports.nix { inherit lib; };

  builders = import ../../ControlModule/pipeline/builders.nix {
    inherit lib flakeInputs;
  };

  renderHostNetworkImpl =
    {
      hostName,
      hostContext ? null,
      cpm,
      inventory ? { },
    }:
    import ../render/host-network.nix {
      inherit
        lib
        hostName
        hostContext
        cpm
        inventory
        ;
    };

  renderDryConfigImpl =
    {
      cpm ? null,
      cpmPath ? null,
      inventory ? { },
      inventoryPath ? null,
      exampleDir ? null,
      debug ? false,
    }:
    import ../render/dry-config-output.nix {
      repoRoot = builtins.toString repoRoot;
      inherit
        cpm
        cpmPath
        inventory
        inventoryPath
        exampleDir
        debug
        ;
    };

  hostBuilders = import ./host-build.nix {
    inherit
      lib
      selectors
      builders
      ;
    renderHostNetwork = renderHostNetworkImpl;
  };

  dryRenderBuild = import ./dry-render-build.nix {
    inherit
      selectors
      builders
      ;
    renderDryConfig = renderDryConfigImpl;
  };

  hostBuild = import ./module-host-build.nix {
    inherit
      lib
      selectors
      ;
    buildHostFromPaths = hostBuilders.buildHostFromPaths;
  };

  host = import ./host/default.nix {
    inherit
      lib
      selectors
      ;
    buildHostFromPaths = hostBuilders.buildHostFromPaths;
  };

  bridges = import ./bridges/default.nix {
    inherit
      lib
      selectors
      ;
    buildHostFromPaths = hostBuilders.buildHostFromPaths;
  };

  containers = import ./containers/default.nix {
    inherit
      lib
      selectors
      ;
    buildHostFromPaths = hostBuilders.buildHostFromPaths;
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
    loadIntent = selectors.importMaybeFunction;
    loadInventory = selectors.importMaybeFunction;
    loadControlPlane = selectors.loadStructuredPath;

    inherit (builders)
      buildCompiler
      buildForwarding
      buildControlPlane
      buildCompilerFromPaths
      buildForwardingFromPaths
      buildControlPlaneFromPaths
      ;

    inherit (hostBuilders)
      buildHost
      buildHostFromPaths
      buildHostFromOutPath
      ;

    inherit (dryRenderBuild)
      buildAndRenderFromPaths
      ;

    renderHostNetwork = renderHostNetworkImpl;
    renderDryConfig = renderDryConfigImpl;
  };
}
