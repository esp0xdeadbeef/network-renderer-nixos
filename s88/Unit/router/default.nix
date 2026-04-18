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
  routerInputs = import ./lookup/default.nix {
    inherit
      outPath
      lib
      config
      selector
      hostContext
      globalInventory
      ;
  };
in
{
  imports = [
    "${outPath}/library/10-vms/nixos-shell-vm/host-config-routers-without-network"
    ../../EquipmentModule/default.nix
  ];

  _module.args = {
    fabricInputs = routerInputs.fabricInputs;
    globalInventory = routerInputs.resolvedInventory;
    hostContext = routerInputs.resolvedHostContext;
    hostSelector = routerInputs.hostSelector;

    activeRoleNames = [ ];
    activeRoles = { };
    s88RoleName = null;
    s88Role = null;
  };
}
