{
  lib,
  selectors,
  buildHostFromPaths,
}:

{
  pkgs,
  outPath,
  hostName,
  inventoryPath ? null,
  selectorFile ? "s88/ControlModule/network/api/module-host-build.nix",
  containerSelection ? { },
}:

let
  system = pkgs.stdenv.hostPlatform.system;

  resolvedPaths = selectors.pathsFromOutPath {
    inherit outPath;
  };

  resolvedIntentPath = resolvedPaths.intentPath;

  resolvedInventoryPath =
    if inventoryPath != null then inventoryPath else resolvedPaths.inventoryPath;

  builtHost = buildHostFromPaths {
    intentPath = resolvedIntentPath;
    inventoryPath = resolvedInventoryPath;
    selector = hostName;
    inherit
      system
      selectorFile
      ;
    file = selectorFile;
  };

  selectedContainers = import ./container-selection.nix {
    inherit
      lib
      containerSelection
      ;
    containers = builtHost.renderedHost.containers or { };
  };

  renderedHostNetwork = builtHost.renderedHost // {
    containers = selectedContainers;
  };

  debugPayload = import ./debug-payload.nix {
    inherit
      lib
      system
      hostName
      renderedHostNetwork
      ;
    hostContext = builtHost.hostContext;
    intent = builtHost.fabricInputs;
    globalInventory = builtHost.globalInventory;
    compilerOut = builtHost.compilerOut;
    forwardingOut = builtHost.forwardingOut;
    controlPlaneOut = builtHost.controlPlaneOut;
    intentPath = resolvedIntentPath;
    inventoryPath = resolvedInventoryPath;
  };
in
{
  inherit renderedHostNetwork debugPayload;

  moduleArgs = {
    globalInventory = builtHost.globalInventory;
    hostContext = builtHost.hostContext;
    intent = builtHost.fabricInputs;
    compilerOut = builtHost.compilerOut;
    forwardingOut = builtHost.forwardingOut;
    controlPlaneOut = builtHost.controlPlaneOut;
    inherit renderedHostNetwork;
  };
}
