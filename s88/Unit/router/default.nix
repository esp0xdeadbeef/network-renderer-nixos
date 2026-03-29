{
  outPath,
  lib,
  config,
  selector ? null,
  hostContext ? { },
  globalInventory ? { },
  ...
}:

let
  hostQuery = import ../../ControlModule/network/lookup/host-query.nix { inherit lib; };

  paths = hostQuery.pathsFromOutPath {
    inherit outPath;
  };

  queried = hostQuery.query {
    selector = if selector != null then selector else config.networking.hostName;
    intentPath = paths.intentPath;
    inventoryPath = paths.inventoryPath;
    file = "s88/Unit/router/default.nix";
  };

  resolvedHostContext = if hostContext != { } then hostContext else queried.hostContext;
  resolvedInventory = if globalInventory != { } then globalInventory else queried.globalInventory;
in
{
  imports = [
    "${outPath}/library/10-vms/nixos-shell-vm/host-config-routers-without-network"
    ../../EquipmentModule/network/default.nix
  ];

  _module.args = {
    fabricInputs = queried.fabricInputs;
    globalInventory = resolvedInventory;
    hostContext = resolvedHostContext;
    hostSelector = if selector != null then selector else config.networking.hostName;

    activeRoleNames = [ ];
    activeRoles = { };
    s88RoleName = null;
    s88Role = null;
  };
}
