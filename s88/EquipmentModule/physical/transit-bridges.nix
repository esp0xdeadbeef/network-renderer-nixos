{ lib
, deploymentHostName
, deploymentHost
, realizationNodes
,
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
      map
        (
          transitName:
          let
            transit = explicitTransitBridges.${transitName};
          in
          if transit ? parentUplink && builtins.isString transit.parentUplink then
            transit.parentUplink
          else
            null
        )
        (sortedAttrNames explicitTransitBridges)
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

  # Collect bridge and direct attachments from realization model ports.
  # Transit bridges are identified by explicit attach.vlan metadata
  # (set by CPM normalizeAttach from bridgeDef.vlan in inventory).
  # Naming-inference (tr[0-9]+ VLAN extraction) is prohibited per
  # SMS FS-310-HDS-010-SDS-010-SMS-120.
  synthesizedTransitAttachments = lib.unique (
    builtins.filter (entry: entry != null) (
      lib.concatMap
        (
          nodeName:
          let
            node = realizationNodes.${nodeName};
            ports = if node ? ports && builtins.isAttrs node.ports then node.ports else { };
          in
          if (node.host or null) == deploymentHostName then
            lib.concatMap
              (
                portName:
                let
                  port = ports.${portName};
                  attach = if port ? attach && builtins.isAttrs port.attach then port.attach else { };

                  bridgeEntry =
                    if
                      (attach.kind or null) == "bridge"
                      && attach ? bridge
                      && builtins.isString attach.bridge
                      && attach ? vlan
                    then
                      {
                        name = attach.bridge;
                        vlan = attach.vlan;
                      }
                      // lib.optionalAttrs (attach ? parentUplink && builtins.isString attach.parentUplink) {
                        inherit (attach) parentUplink;
                      }
                    else
                      null;

                  directEntry =
                    if (attach.kind or null) == "direct" && port ? link && builtins.isString port.link then
                      { name = port.link; }
                    else
                      null;
                in
                lib.filter (e: e != null) [
                  bridgeEntry
                  directEntry
                ]
              )
              (builtins.attrNames ports)
          else
            [ ]
        )
        (builtins.attrNames realizationNodes)
    )
  );

  synthesizedTransitNames = map (entry: entry.name) synthesizedTransitAttachments;

  synthesizedTransitBridgeNameMap = hostNaming.ensureUnique synthesizedTransitNames;

  synthesizedTransitBridges = builtins.listToAttrs (
    map
      (entry: {
        name = entry.name;
        value = {
          name = synthesizedTransitBridgeNameMap.${entry.name};
        }
        // lib.optionalAttrs (entry ? vlan) {
          vlan = entry.vlan;
        }
        // lib.optionalAttrs (entry ? parentUplink) {
          parentUplink = entry.parentUplink;
        }
        // lib.optionalAttrs (!(entry ? vlan) && defaultParentUplinkName != null) {
          parentUplink = defaultParentUplinkName;
        };
      })
      synthesizedTransitAttachments
  );

  transitBridges = synthesizedTransitBridges // explicitTransitBridges;
in
{
  inherit transitBridges;
}
