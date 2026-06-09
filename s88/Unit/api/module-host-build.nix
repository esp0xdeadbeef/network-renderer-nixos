{ lib ? null
, selectors
, buildHostFromPaths
,
}:

{ lib ? null
, system ? "x86_64-linux"
, outPath
, hostName
, inventoryPath ? null
, inventoryRenderer ? null
, selectorFile ? "s88/Unit/api/module-host-build.nix"
, containerDefaults ? { }
, disabled ? { }
, containerSelection ? { }
,
}:

let
  resolvedOutPath = builtins.toPath outPath;

  effectiveLib =
    if lib != null then
      lib
    else
      throw ''
        s88/Unit/api/module-host-build.nix: lib is required
      '';

  resolvedPaths = selectors.pathsFromOutPath {
    outPath = resolvedOutPath;
  };

  resolvedIntentPath = resolvedPaths.intentPath;

  resolvedInventoryPath =
    if inventoryPath != null then
      inventoryPath
    else if inventoryRenderer != null && builtins.pathExists "${resolvedOutPath}/getResolvedInventory.nix" then
      builtins.toFile "network-renderer-nixos-resolved-inventory-${inventoryRenderer}.nix" ''
        import ${resolvedOutPath}/getResolvedInventory.nix { renderer = "${inventoryRenderer}"; }
      ''
    else
      resolvedPaths.inventoryPath;

  builtHost = buildHostFromPaths {
    intentPath = resolvedIntentPath;
    inventoryPath = resolvedInventoryPath;
    selector = hostName;
    inherit
      system
      containerDefaults
      disabled
      ;
    file = selectorFile;
  };

  selectedContainers = import ../../ControlModule/api/container-selection.nix {
    lib = effectiveLib;
    inherit
      containerSelection
      ;
    containers = builtHost.renderedHost.containers or { };
  };

  renderedHostNetwork = builtHost.renderedHost // {
    containers = selectedContainers;
  };

  debugPayload = import ../../ControlModule/api/debug-payload.nix {
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

  artifactModule = import ../../ControlModule/api/artifact-module.nix { inherit debugPayload; };

  moduleArgs = {
    globalInventory = builtHost.globalInventory;
    hostContext = builtHost.hostContext;
    intent = builtHost.fabricInputs;
    fabricInputs = builtHost.fabricInputs;
    compilerOut = builtHost.compilerOut;
    forwardingOut = builtHost.forwardingOut;
    controlPlaneOut = builtHost.controlPlaneOut;
    inherit renderedHostNetwork;
  };
in
{
  inherit renderedHostNetwork debugPayload;

  inherit artifactModule moduleArgs;

  nixosModule = {
    imports = [ artifactModule ];

    _module.args = moduleArgs;

    networking.useNetworkd = true;
    systemd.network.enable = true;
    networking.useDHCP = false;
    networking.useHostResolvConf = effectiveLib.mkForce false;

    systemd.network.netdevs = renderedHostNetwork.netdevs or { };
    systemd.network.networks = renderedHostNetwork.networks or { };
    containers = renderedHostNetwork.containers or { };
  };
}
