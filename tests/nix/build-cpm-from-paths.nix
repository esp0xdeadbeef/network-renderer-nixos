let
  repoRoot = builtins.getEnv "REPO_ROOT";
  intentPath = /. + builtins.getEnv "INTENT_PATH";
  inventoryPath = /. + builtins.getEnv "INVENTORY_PATH";

  flake = builtins.getFlake repoRoot;
in
flake.lib.renderer.buildControlPlaneFromPaths {
  inherit intentPath inventoryPath;
}
