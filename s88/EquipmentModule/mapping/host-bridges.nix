{
  lib,
  attachTargetsRuntime,
  deploymentHost ? { },
}:

let
  hostNaming = import ../../../lib/host-naming.nix { inherit lib; };
  sortedAttrNames = attrs: lib.sort builtins.lessThan (builtins.attrNames attrs);

  explicitBridgeNames =
    if deploymentHost ? bridgeNetworks && builtins.isAttrs deploymentHost.bridgeNetworks then
      sortedAttrNames deploymentHost.bridgeNetworks
    else
      [ ];

  bridgeNamesRaw = lib.sort builtins.lessThan (
    lib.unique (
      lib.filter builtins.isString (map (target: target.hostBridgeName or null) attachTargetsRuntime)
      ++ explicitBridgeNames
    )
  );

  bridgeNameMap = hostNaming.ensureUnique bridgeNamesRaw;

  bridges = builtins.listToAttrs (
    map (bridgeName: {
      name = bridgeName;
      value = {
        originalName = bridgeName;
        renderedName = bridgeNameMap.${bridgeName};
        explicitDeploymentBridge = builtins.hasAttr bridgeName (
          if deploymentHost ? bridgeNetworks && builtins.isAttrs deploymentHost.bridgeNetworks then
            deploymentHost.bridgeNetworks
          else
            { }
        );
      };
    }) bridgeNamesRaw
  );

  attachTargetsBase = map (
    target:
    let
      iface = target.interface or { };
      hostBridgeName = target.hostBridgeName;
    in
    target
    // {
      baseRenderedHostBridgeName =
        if builtins.hasAttr hostBridgeName bridgeNameMap then
          bridgeNameMap.${hostBridgeName}
        else
          hostNaming.shorten hostBridgeName;
      renderedIfName = iface.renderedIfName or null;
      addresses = iface.addresses or [ ];
      routes = iface.routes or [ ];
      connectivity = target.connectivity or (iface.connectivity or { });
      interface = iface;
    }
  ) attachTargetsRuntime;
in
{
  inherit
    bridgeNamesRaw
    bridgeNameMap
    bridges
    attachTargetsBase
    ;
}
