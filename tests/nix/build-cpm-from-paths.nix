let
  repoRoot = builtins.getEnv "REPO_ROOT";
  intentPath = builtins.getEnv "INTENT_PATH";
  inventoryPath = builtins.getEnv "INVENTORY_PATH";

  flake = builtins.getFlake repoRoot;
  cpmFlake = flake.inputs.network-control-plane-model;
  system = "x86_64-linux";
in
cpmFlake.lib.${system}.compileAndBuildFromPaths {
  inputPath = /. + intentPath;
  inventoryPath = /. + inventoryPath;
  validateForwardingModel = false;
  validateRuntimeModel = false;
}
