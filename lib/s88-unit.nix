{
  outPath,
  lib,
  config,
  boxContext ? { },
  globalInventory ? { },
  ...
}:

let
  runtimeContext = import ./runtime-context.nix { inherit lib; };
  queried = (import ./query-box.nix { inherit lib; }).queryFromOutPath {
    inherit outPath;
    hostname = config.networking.hostName;
    file = "lib/s88-unit.nix";
  };

  resolvedBoxContext =
    if boxContext != { } then boxContext else queried.boxContext;

  resolvedInventory =
    if globalInventory != { } then globalInventory else queried.globalInventory;

  deploymentHostName =
    if resolvedBoxContext ? deploymentHostName
      && builtins.isString resolvedBoxContext.deploymentHostName
    then
      resolvedBoxContext.deploymentHostName
    else
      config.networking.hostName;

  controlPlaneOut =
    if resolvedBoxContext ? controlPlaneOut then
      resolvedBoxContext.controlPlaneOut
    else
      null;

  matchedRole =
    if controlPlaneOut != null then
      let
        roles =
          lib.unique (
            map
              (unitName:
                runtimeContext.roleForUnit {
                  cpm = controlPlaneOut;
                  inventory = resolvedInventory;
                  inherit unitName;
                  file = "lib/s88-unit.nix";
                })
              (
                runtimeContext.unitNamesForRoleOnDeploymentHost {
                  cpm = controlPlaneOut;
                  inventory = resolvedInventory;
                  inherit deploymentHostName;
                  role = "access";
                  file = "lib/s88-unit.nix";
                }
                ++ runtimeContext.unitNamesForRoleOnDeploymentHost {
                  cpm = controlPlaneOut;
                  inventory = resolvedInventory;
                  inherit deploymentHostName;
                  role = "core";
                  file = "lib/s88-unit.nix";
                }
                ++ runtimeContext.unitNamesForRoleOnDeploymentHost {
                  cpm = controlPlaneOut;
                  inventory = resolvedInventory;
                  inherit deploymentHostName;
                  role = "policy";
                  file = "lib/s88-unit.nix";
                }
                ++ runtimeContext.unitNamesForRoleOnDeploymentHost {
                  cpm = controlPlaneOut;
                  inventory = resolvedInventory;
                  inherit deploymentHostName;
                  role = "upstream-selector";
                  file = "lib/s88-unit.nix";
                }
              )
          );
      in
      if builtins.length roles == 1 then builtins.head roles else null
    else
      null;

  roles = import ./s88-role-registry.nix { inherit lib; };

  s88RoleName =
    if matchedRole != null && builtins.hasAttr matchedRole roles then
      matchedRole
    else
      throw "lib/s88-unit.nix: could not resolve a unique router role";

  s88Role = roles.${s88RoleName};
in
{
  imports = [
    "${outPath}/library/10-vms/nixos-shell-vm/host-config-routers-without-network"
    ../s88/CM/network/default.nix
  ];

  _module.args = {
    inherit (queried) fabricInputs globalInventory;
    inherit resolvedBoxContext s88Role s88RoleName;
    boxContext = resolvedBoxContext;
  };
}
