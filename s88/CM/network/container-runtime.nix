{
  config,
  lib,
  controlPlaneOut,
  globalInventory,
  boxContext,
  s88Role,
  s88RoleName,
  ...
}:

let
  runtimeContext = import ../../../lib/runtime-context.nix { inherit lib; };
  realizationPorts = import ../../../lib/realization-ports.nix { inherit lib; };

  sortedAttrNames = attrs: lib.sort builtins.lessThan (builtins.attrNames attrs);

  deploymentHostName =
    if boxContext ? deploymentHostName && builtins.isString boxContext.deploymentHostName then
      boxContext.deploymentHostName
    else
      config.networking.hostName;

  selectedUnits = runtimeContext.unitNamesForRoleOnDeploymentHost {
    cpm = controlPlaneOut;
    inventory = globalInventory;
    inherit deploymentHostName;
    role = s88Role.runtimeRole;
    file = "s88/CM/network/container-runtime.nix";
  };

  profilePath =
    if s88Role ? container
      && builtins.isAttrs s88Role.container
      && s88Role.container ? profilePath
    then
      s88Role.container.profilePath
    else
      null;

  additionalCapabilities =
    if s88Role ? container
      && builtins.isAttrs s88Role.container
      && s88Role.container ? additionalCapabilities
      && builtins.isList s88Role.container.additionalCapabilities
    then
      s88Role.container.additionalCapabilities
    else
      [ ];

  bindMounts =
    if s88Role ? container
      && builtins.isAttrs s88Role.container
      && s88Role.container ? bindMounts
      && builtins.isAttrs s88Role.container.bindMounts
    then
      s88Role.container.bindMounts
    else
      { };

  allowedDevices =
    if s88Role ? container
      && builtins.isAttrs s88Role.container
      && s88Role.container ? allowedDevices
      && builtins.isList s88Role.container.allowedDevices
    then
      s88Role.container.allowedDevices
    else
      [ ];

  mkContainer =
    unitName:
    let
      realizationNode = realizationPorts.nodeForUnit {
        inventory = globalInventory;
        inherit unitName;
        file = "s88/CM/network/container-runtime.nix";
      };

      attachMap = realizationPorts.attachMapForUnit {
        inventory = globalInventory;
        inherit unitName;
        file = "s88/CM/network/container-runtime.nix";
      };

      runtimeTarget = runtimeContext.runtimeTargetForUnit {
        cpm = controlPlaneOut;
        inherit unitName;
        file = "s88/CM/network/container-runtime.nix";
      };

      extraVeths =
        builtins.listToAttrs (
          map
            (portName: {
              name = portName;
              value = {
                hostBridge = attachMap.${portName}.name;
              };
            })
            (sortedAttrNames attachMap)
        );
    in
    {
      name = unitName;
      value = {
        autoStart = true;
        privateNetwork = true;
        inherit bindMounts allowedDevices extraVeths;

        additionalCapabilities =
          [
            "CAP_NET_ADMIN"
            "CAP_NET_RAW"
          ]
          ++ additionalCapabilities;

        specialArgs = {
          inherit
            unitName
            deploymentHostName
            realizationNode
            runtimeTarget
            controlPlaneOut
            globalInventory
            boxContext
            s88Role
            s88RoleName
            ;
        };

        config = { ... }: {
          imports =
            lib.optionals (profilePath != null) [
              profilePath
            ];

          networking.hostName = unitName;
        };
      };
    };
in
{
  containers =
    builtins.listToAttrs (map mkContainer selectedUnits);
}
