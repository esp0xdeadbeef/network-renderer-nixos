{
  lib ? null,
  selectors,
  buildHostFromPaths,
}:

{
  lib ? null,
  system ? "x86_64-linux",
  outPath,
  hostName,
  inventoryPath ? null,
  selectorFile ? "s88/ControlModule/api/module-host-build.nix",
  containerSelection ? { },
}:

let
  effectiveLib =
    if lib != null then
      lib
    else
      throw ''
        s88/ControlModule/api/module-host-build.nix: lib is required
      '';

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
    inherit system;
    file = selectorFile;
  };

  selectedContainers = import ./container-selection.nix {
    lib = effectiveLib;
    inherit
      containerSelection
      ;
    containers = builtHost.renderedHost.containers or { };
  };

  renderedHostNetwork = builtHost.renderedHost // {
    containers = selectedContainers;
  };

  debugPayload = import ./debug-payload.nix {
    lib = effectiveLib;
    inherit
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
