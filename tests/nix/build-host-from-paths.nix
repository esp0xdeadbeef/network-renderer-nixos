{ selector ? builtins.getEnv "SELECTOR"
, intentPath ? builtins.getEnv "INTENT_PATH"
, inventoryPath ? builtins.getEnv "INVENTORY_PATH"
, system ? "x86_64-linux"
, ...
}@args:
let
  repoRoot = builtins.getEnv "REPO_ROOT";
  flake = builtins.getFlake ("path:" + repoRoot);
  lib = flake.inputs.nixpkgs.lib;

  cpmFlake = flake.inputs.network-control-plane-model;

  cpmOut = cpmFlake.lib.${system}.compileAndBuildFromPaths {
    inputPath = intentPath;
    inherit inventoryPath;
    validateForwardingModel = false;
    validateRuntimeModel = false;
  };

  hostBuild = flake.lib.renderer.buildHostFromControlPlane {
    controlPlaneOut = cpmOut;
    inherit selector system;
    containerDefaults = args.containerDefaults or { };
    disabled = args.disabled or { };
  };
in
hostBuild
