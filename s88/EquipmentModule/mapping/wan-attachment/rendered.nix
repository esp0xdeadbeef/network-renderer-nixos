{
  lib,
  lookup,
  assignment,
  attachTargetsBase,
}:

let
  hostNaming = import ../../../../lib/host-naming.nix { inherit lib; };

  normalizeIpv4 =
    value:
    let
      ipv4 = if builtins.isAttrs value then value else { };
      method = ipv4.method or null;
    in
    ipv4
    // lib.optionalAttrs (method == "dhcp") {
      enable = true;
      dhcp = true;
    };

  normalizeIpv6 =
    value:
    let
      ipv6 = if builtins.isAttrs value then value else { };
      method = ipv6.method or null;
    in
    ipv6
    // lib.optionalAttrs (method == "dhcp" || method == "dhcp6") {
      enable = true;
      dhcp = true;
    }
    // lib.optionalAttrs (method == "slaac") {
      enable = true;
      acceptRA = true;
    };

  uplinkBridgeNamesRaw = lib.unique (
    lib.filter builtins.isString (
      map (uplinkName: lookup.uplinksRaw.${uplinkName}.bridge or null) lookup.uplinkNames
    )
  );

  uplinkBridgeNameMap = hostNaming.ensureUnique uplinkBridgeNamesRaw;

  renderedHostBridgeNameForWanGroup =
    wanGroupName:
    let
      uplinkName = assignment.wanGroupToUplinkName.${wanGroupName};
      uplink = lookup.uplinksRaw.${uplinkName};

      originalBridge =
        if uplink ? bridge && builtins.isString uplink.bridge then
          uplink.bridge
        else
          throw ''
            s88/EquipmentModule/mapping/wan-attachment.nix: uplink '${uplinkName}' assigned to WAN group '${wanGroupName}' is missing bridge

            uplink:
            ${builtins.toJSON uplink}
          '';
    in
    uplinkBridgeNameMap.${originalBridge};

  attachTargets = builtins.seq assignment.validateStrictWanRendering (
    map (
      target:
      let
        wanGroupName = lookup.wanGroupNameForTarget target;

        assignedUplinkName =
          if wanGroupName != null && builtins.hasAttr wanGroupName assignment.wanGroupToUplinkName then
            assignment.wanGroupToUplinkName.${wanGroupName}
          else
            null;
      in
      target
      // {
        inherit assignedUplinkName;
        renderedHostBridgeName =
          if assignedUplinkName != null then
            renderedHostBridgeNameForWanGroup wanGroupName
          else
            target.baseRenderedHostBridgeName;
      }
    ) attachTargetsBase
  );

  localAttachTargets = attachTargets;

  maybePreferredAttachTarget =
    predicate:
    let
      matches = lib.filter predicate localAttachTargets;
    in
    if builtins.length matches == 1 then builtins.head matches else null;

  wanAttachTarget = maybePreferredAttachTarget (target: lookup.sourceKindForTarget target == "wan");

  fabricAttachTarget = maybePreferredAttachTarget (
    target: lookup.sourceKindForTarget target == "p2p"
  );

  renderedHostBridgeNameForAssignedUplink =
    uplinkName:
    let
      matches = lib.filter (target: (target.assignedUplinkName or null) == uplinkName) localAttachTargets;

      renderedNames = lib.unique (map (target: target.renderedHostBridgeName) matches);
    in
    if renderedNames == [ ] then
      null
    else if builtins.length renderedNames == 1 then
      builtins.head renderedNames
    else
      throw ''
        s88/EquipmentModule/mapping/wan-attachment.nix: uplink '${uplinkName}' resolved to multiple rendered WAN bridges

        matches:
        ${builtins.toJSON matches}
      '';

  uplinks = builtins.mapAttrs (
    uplinkName: uplink:
    let
      originalBridge =
        if uplink ? bridge && builtins.isString uplink.bridge then
          uplink.bridge
        else
          throw ''
            s88/EquipmentModule/mapping/wan-attachment.nix: uplink '${uplinkName}' is missing bridge

            uplink:
            ${builtins.toJSON uplink}
          '';

      assignedWanRenderedBridge = renderedHostBridgeNameForAssignedUplink uplinkName;

      renderedBridge =
        if assignedWanRenderedBridge != null then
          assignedWanRenderedBridge
        else if uplinkName == assignment.wanUplinkName && wanAttachTarget != null then
          wanAttachTarget.renderedHostBridgeName
        else if
          assignment.fabricUplinkName != null
          && uplinkName == assignment.fabricUplinkName
          && fabricAttachTarget != null
        then
          fabricAttachTarget.renderedHostBridgeName
        else
          uplinkBridgeNameMap.${originalBridge};

      mode =
        if uplink ? mode && builtins.isString uplink.mode then
          uplink.mode
        else if uplink ? parent && builtins.isString uplink.parent && uplink ? vlan then
          "vlan"
        else
          null;
    in
    uplink
    // {
      inherit originalBridge;
      bridge = renderedBridge;
      ipv4 = normalizeIpv4 (uplink.ipv4 or { });
      ipv6 = normalizeIpv6 (uplink.ipv6 or { });
    }
    // lib.optionalAttrs (mode != null) { inherit mode; }
  ) lookup.uplinksRaw;
in
{
  inherit
    attachTargets
    localAttachTargets
    uplinks
    ;

  hostHasUplinks = lookup.hostHasUplinks;
  wanUplinkName = assignment.wanUplinkName;
  fabricUplinkName = assignment.fabricUplinkName;
}
