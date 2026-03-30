{
  outPath,
  lib,
  config,
  selector ? null,
  hostContext ? { },
  globalInventory ? { },
}:

let
  hostQuery = import ../../../ControlModule/lookup/host-query.nix { inherit lib; };

  hostSelector = if selector != null then selector else config.networking.hostName;

  paths = hostQuery.pathsFromOutPath {
    inherit outPath;
  };

  queried = hostQuery.query {
    selector = hostSelector;
    intentPath = paths.intentPath;
    inventoryPath = paths.inventoryPath;
    file = "s88/Unit/router/lookup/default.nix";
  };

  resolvedHostContext = if hostContext != { } then hostContext else queried.hostContext;
  resolvedInventory = if globalInventory != { } then globalInventory else queried.globalInventory;
in
{
  inherit
    paths
    queried
    hostSelector
    resolvedHostContext
    resolvedInventory
    ;

  fabricInputs = queried.fabricInputs;
}
