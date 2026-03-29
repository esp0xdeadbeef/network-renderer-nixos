{
  lib,
  attachTargetsRuntime,
}:

let
  hostNaming = import ../../../../lib/host-naming.nix { inherit lib; };
  bridgeRenderer = import ../render/bridge-artifacts.nix { inherit lib; };

  bridgeNamesRaw = bridgeRenderer.bridgeNamesRawForAttachTargets attachTargetsRuntime;

  bridgeNameMap = bridgeRenderer.bridgeNameMapForAttachTargets {
    attachTargets = attachTargetsRuntime;
    shorten = hostNaming.shorten;
    ensureUnique = hostNaming.ensureUnique;
  };

  bridges = builtins.listToAttrs (
    map (bridgeName: {
      name = bridgeName;
      value = {
        originalName = bridgeName;
        renderedName = bridgeNameMap.${bridgeName};
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
