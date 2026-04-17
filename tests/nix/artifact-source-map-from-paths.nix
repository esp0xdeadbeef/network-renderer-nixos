let
  repoRoot = builtins.getEnv "REPO_ROOT";
  system = builtins.getEnv "NIX_SYSTEM_VALUE";
  intentPath = /. + builtins.getEnv "INTENT_PATH";
  inventoryPath = /. + builtins.getEnv "INVENTORY_PATH";

  renderer = (builtins.getFlake repoRoot).libBySystem.${system};

  etcEntries =
    (renderer.artifacts.controlPlaneSplitFromPaths {
      inherit intentPath inventoryPath;
      fileName = "control-plane-model.json";
      directory = "network-artifacts";
    }).environment.etc;

  artifactNames = builtins.filter (name: builtins.match "network-artifacts/.*" name != null) (
    builtins.attrNames etcEntries
  );
in
builtins.listToAttrs (
  map (name: {
    inherit name;
    value = toString etcEntries.${name}.source;
  }) artifactNames
)
