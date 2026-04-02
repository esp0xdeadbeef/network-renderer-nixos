{
  lib,
  deploymentHostName,
  deploymentHost,
  realizationNodes,
}:

let
  hostNaming = import ../../../lib/host-naming.nix { inherit lib; };

  sortedAttrNames = attrs: lib.sort builtins.lessThan (builtins.attrNames attrs);

  explicitTransitBridges =
    if !(deploymentHost ? transitBridges) then
      { }
    else if builtins.isAttrs deploymentHost.transitBridges then
      deploymentHost.transitBridges
    else
      throw ''
        s88/EquipmentModule/physical/transit-bridges.nix: deployment host '${deploymentHostName}' has non-attr transitBridges

        deployment host:
        ${builtins.toJSON deploymentHost}
      '';

  uplinks =
    if deploymentHost ? uplinks && builtins.isAttrs deploymentHost.uplinks then
      deploymentHost.uplinks
    else
      { };

  uplinkNames = sortedAttrNames uplinks;

  explicitParentUplinkNames = lib.unique (
    lib.filter builtins.isString (
      map (
        transitName:
        let
          transit = explicitTransitBridges.${transitName};
        in
        if transit ? parentUplink && builtins.isString transit.parentUplink then
          transit.parentUplink
        else
          null
      ) (sortedAttrNames explicitTransitBridges)
    )
  );

  defaultParentUplinkName =
    if builtins.length explicitParentUplinkNames == 1 then
      builtins.head explicitParentUplinkNames
    else if uplinks ? fabric && builtins.isAttrs uplinks.fabric then
      "fabric"
    else if uplinks ? trunk && builtins.isAttrs uplinks.trunk then
      "trunk"
    else if builtins.length uplinkNames == 1 then
      builtins.head uplinkNames
    else
      null;

  parseTransitVlan =
    transitName:
    if builtins.match "tr[0-9]+" transitName != null then
      builtins.fromJSON (builtins.substring 2 (builtins.stringLength transitName - 2) transitName)
    else
      null;

  synthesizedTransitNames = lib.unique (
    lib.concatMap (
      nodeName:
      let
        node = realizationNodes.${nodeName};
        ports = if node ? ports && builtins.isAttrs node.ports then node.ports else { };
      in
      if (node.host or null) == deploymentHostName then
        lib.concatMap (
          portName:
          let
            port = ports.${portName};
            attach = if port ? attach && builtins.isAttrs port.attach then port.attach else { };

            bridgeName =
              if
                (attach.kind or null) == "bridge"
                && attach ? bridge
                && builtins.isString attach.bridge
                && parseTransitVlan attach.bridge != null
              then
                attach.bridge
              else
                null;

            directName =
              if (attach.kind or null) == "direct" && port ? link && builtins.isString port.link then
                port.link
              else
                null;
          in
          lib.filter builtins.isString [
            bridgeName
            directName
          ]
        ) (builtins.attrNames ports)
      else
        [ ]
    ) (builtins.attrNames realizationNodes)
  );

  synthesizedTransitBridgeNameMap = hostNaming.ensureUnique synthesizedTransitNames;

  synthesizedTransitBridges = builtins.listToAttrs (
    map (transitName: {
      name = transitName;
      value = {
        name = synthesizedTransitBridgeNameMap.${transitName};
      }
      // lib.optionalAttrs (parseTransitVlan transitName != null) {
        vlan = parseTransitVlan transitName;
      }
      // lib.optionalAttrs (parseTransitVlan transitName != null && defaultParentUplinkName != null) {
        parentUplink = defaultParentUplinkName;
      };
    }) synthesizedTransitNames
  );

  transitBridges = synthesizedTransitBridges // explicitTransitBridges;
in
{
  inherit transitBridges;
}
