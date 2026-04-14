{ lib }:
{
  containerModel,
  deploymentHostName,
}:
let
  sortedAttrNames = attrs: lib.sort builtins.lessThan (builtins.attrNames attrs);

  ensureAttrs =
    name: value:
    if builtins.isAttrs value then
      value
    else
      throw "network-renderer-nixos: expected ${name} to be an attribute set";

  ensureString =
    name: value:
    if builtins.isString value && value != "" then
      value
    else
      throw "network-renderer-nixos: expected ${name} to be a non-empty string";

  containerNames =
    if containerModel ? containers && builtins.isAttrs containerModel.containers then
      sortedAttrNames containerModel.containers
    else
      [ ];

  bridgeNames = lib.unique (
    lib.concatMap (
      containerName:
      let
        container =
          ensureAttrs "simulated container '${containerName}'"
            containerModel.containers.${containerName};

        interfaces =
          if container ? interfaces && builtins.isAttrs container.interfaces then
            container.interfaces
          else
            { };
      in
      lib.concatMap (
        interfaceName:
        let
          interface =
            ensureAttrs "simulated container '${containerName}' interface '${interfaceName}'"
              interfaces.${interfaceName};
        in
        if interface ? hostBridge && interface.hostBridge != null then
          [
            (ensureString "simulated container '${containerName}' interface '${interfaceName}'.hostBridge" interface.hostBridge)
          ]
        else
          [ ]
      ) (sortedAttrNames interfaces)
    ) containerNames
  );

  bridges = builtins.listToAttrs (
    map (bridgeName: {
      name = bridgeName;
      value = {
        inherit bridgeName;
      };
    }) bridgeNames
  );
in
{
  hostName = deploymentHostName;
  deploymentHostName = deploymentHostName;
  bridges = bridges;
  debug = {
    hostName = deploymentHostName;
    bridges = bridgeNames;
  };
}
