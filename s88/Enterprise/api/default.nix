{
  lib,
  repoRoot ? ../../..,
  flakeInputs ? { },
}:

let
  selectors = import ../../ControlModule/lookup/host-query.nix { inherit lib; };
  realizationPorts = import ../../ControlModule/physical/realization-ports.nix {
    inherit lib;
  };

  builders = import ../../ControlModule/pipeline/builders.nix {
    inherit lib flakeInputs;
  };

  renderHostNetworkImpl =
    {
      hostName,
      cpm,
      inventory ? { },
    }:
    import ../../ControlModule/render/host-network.nix {
      inherit
        lib
        hostName
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
    import ../../ControlModule/render/dry-config-output.nix {
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

  hostBuilders = import ../../ControlModule/api/host-build.nix {
    inherit
      lib
      selectors
      builders
      ;
    renderHostNetwork = renderHostNetworkImpl;
    renderDryConfig = renderDryConfigImpl;
  };

  hostBuild = import ../../ControlModule/api/module-host-build.nix {
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
      buildAndRenderFromPaths
      ;

    renderHostNetwork = renderHostNetworkImpl;
    renderDryConfig = renderDryConfigImpl;
  };
}
