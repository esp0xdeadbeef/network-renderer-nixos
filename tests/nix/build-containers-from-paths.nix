{ boxName ? builtins.getEnv "BOX_NAME"
, selector ? builtins.getEnv "SELECTOR"
, intentPath ? builtins.getEnv "INTENT_PATH"
, inventoryPath ? builtins.getEnv "INVENTORY_PATH"
, system ? "x86_64-linux"
, defaults ? { }
, disabled ? { }
, ...
}:
let
  repoRoot = builtins.getEnv "REPO_ROOT";
  flake = builtins.getFlake ("path:" + repoRoot);
  lib = flake.inputs.nixpkgs.lib;

  cpmFlake = flake.inputs.network-control-plane-model;

  cpm = cpmFlake.lib.${system}.compileAndBuildFromPaths {
    inputPath = intentPath;
    inherit inventoryPath;
    validateForwardingModel = false;
    validateRuntimeModel = false;
  };

  containers = flake.lib.containers.buildForBox {
    inherit boxName selector system defaults disabled cpm;
  };
in
containers
