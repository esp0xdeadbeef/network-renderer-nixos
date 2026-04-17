let
  repoRoot = builtins.getEnv "REPO_ROOT";
  system = builtins.getEnv "NIX_SYSTEM_VALUE";
  intentPath = /. + builtins.getEnv "INTENT_PATH";
  inventoryPath = /. + builtins.getEnv "INVENTORY_PATH";

  flake = builtins.getFlake repoRoot;
  renderer = flake.libBySystem.${system};

  built = renderer.renderer.buildControlPlaneFromPaths {
    inherit intentPath inventoryPath;
  };
in
if builtins.isAttrs built && built ? control_plane_model then
  built.control_plane_model
else if builtins.isAttrs built && built ? controlPlaneModel then
  built.controlPlaneModel
else
  built
