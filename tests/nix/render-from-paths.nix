let
  repoRoot = builtins.getEnv "REPO_ROOT";
  system = builtins.getEnv "NIX_SYSTEM_VALUE";
  mode = builtins.getEnv "RENDER_MODE";
  intentPath = /. + builtins.getEnv "INTENT_PATH";
  inventoryPath = /. + builtins.getEnv "INVENTORY_PATH";
  boxName = builtins.getEnv "BOX_NAME";

  flake = builtins.getFlake repoRoot;
  renderer = flake.libBySystem.${system};
in
if mode == "host" then
  renderer.host.build {
    inherit intentPath inventoryPath boxName;
  }
else if mode == "bridges" then
  renderer.bridges.build {
    inherit intentPath inventoryPath boxName;
  }
else if mode == "containers" then
  renderer.containers.buildForBox {
    inherit intentPath inventoryPath boxName;
  }
else if mode == "artifacts" then
  renderer.artifacts.controlPlaneSplitFromPaths {
    inherit intentPath inventoryPath;
    fileName = "control-plane-model.json";
    directory = "network-artifacts";
  }
else
  throw "unknown render mode: ${mode}"
