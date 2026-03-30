{
  lib,
  repoRoot ? ../../..,
  flakeInputs ? { },
}:

let
  selectors = import ../lookup/host-query.nix { inherit lib; };
  realizationPorts = import ../physical/realization-ports.nix { inherit lib; };

  builders = import ../pipeline/builders.nix {
    inherit lib flakeInputs;
  };

  renderHostNetworkImpl =
    {
      hostName,
      cpm,
      inventory ? { },
    }:
    import ../render/host-network.nix {
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
    renderDryConfig = renderDryConfigImpl;
  };

  hostBuild = import ./module-host-build.nix {
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
