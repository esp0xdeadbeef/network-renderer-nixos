{
  lib,
  deploymentHostName,
  deploymentHost,
  cpm,
  inventory ? { },
  attachTargetsBase,
}:

let
  runtimeContext = import ../../../Unit/lookup/runtime-context.nix { inherit lib; };

  sortedAttrNames = attrs: lib.sort builtins.lessThan (builtins.attrNames attrs);

  overlayNameSet =
    let
      data =
        if
          cpm ? control_plane_model
          && builtins.isAttrs cpm.control_plane_model
          && cpm.control_plane_model ? data
          && builtins.isAttrs cpm.control_plane_model.data
        then
          cpm.control_plane_model.data
        else
          { };
      siteOverlayNames =
        enterpriseName:
        siteName:
        let
          site = data.${enterpriseName}.${siteName};
          overlays =
            if builtins.isAttrs (site.overlays or null) then
              builtins.attrNames site.overlays
            else
              [ ];
          overlayReachability =
            if builtins.isAttrs (site.overlayReachability or null) then
              builtins.attrNames site.overlayReachability
            else
              [ ];
        in
        overlays ++ overlayReachability;
      overlayNames = lib.concatMap (
        enterpriseName:
        lib.concatMap (siteName: siteOverlayNames enterpriseName siteName) (
          builtins.attrNames data.${enterpriseName}
        )
      ) (builtins.attrNames data);
    in
    builtins.listToAttrs (
      map (name: {
        inherit name;
        value = true;
      }) (lib.unique (lib.filter builtins.isString overlayNames))
    );

  sourceKindForTarget =
    target:
    if
      target ? connectivity
      && builtins.isAttrs target.connectivity
      && target.connectivity ? sourceKind
      && builtins.isString target.connectivity.sourceKind
    then
      target.connectivity.sourceKind
    else
      null;

  logicalNodeIdentityForTarget =
    target:
    runtimeContext.logicalNodeIdentityForUnit {
      inherit cpm inventory;
      unitName = target.unitName;
      file = "s88/EquipmentModule/mapping/wan-attachment.nix";
    };

  isOverlayTransportTarget =
    target:
    sourceKindForTarget target == "wan"
    && target ? connectivity
    && builtins.isAttrs target.connectivity
    && builtins.isString (target.connectivity.upstream or null)
    && builtins.hasAttr target.connectivity.upstream overlayNameSet;

  wanGroupNameForTarget =
    target:
    if sourceKindForTarget target == "wan" && !isOverlayTransportTarget target then
      logicalNodeIdentityForTarget target
    else
      null;

  uplinksRaw =
    if !(deploymentHost ? uplinks) then
      { }
    else if builtins.isAttrs deploymentHost.uplinks then
      deploymentHost.uplinks
    else
      throw ''
        s88/EquipmentModule/mapping/wan-attachment.nix: deployment host '${deploymentHostName}' has non-attr uplinks

        deployment host:
        ${builtins.toJSON deploymentHost}
      '';

  hostHasUplinks = uplinksRaw != { };

  uplinkNames = sortedAttrNames uplinksRaw;

  wanGroupNames = lib.sort builtins.lessThan (
    lib.unique (lib.filter builtins.isString (map wanGroupNameForTarget attachTargetsBase))
  );

  wanTargetsForGroup =
    wanGroupName: lib.filter (target: wanGroupNameForTarget target == wanGroupName) attachTargetsBase;

  upstreamNamesForWanGroup =
    wanGroupName:
    let
      upstreamNames = lib.unique (
        lib.filter builtins.isString (
          map (target: target.connectivity.upstream or null) (wanTargetsForGroup wanGroupName)
        )
      );
    in
    if builtins.length upstreamNames <= 1 then
      upstreamNames
    else
      throw ''
        s88/EquipmentModule/mapping/wan-attachment.nix: WAN group '${wanGroupName}' resolved to multiple upstream identities

        upstream names:
        ${builtins.toJSON upstreamNames}

        targets:
        ${builtins.toJSON (wanTargetsForGroup wanGroupName)}
      '';

  uplinkMatchKeys =
    uplinkName:
    let
      uplink = uplinksRaw.${uplinkName};
    in
    lib.unique (
      lib.filter builtins.isString [
        uplinkName
        (uplink.name or null)
        (uplink.uplink or null)
        (uplink.upstream or null)
        (uplink.external or null)
        (uplink.provider or null)
        (uplink.bridge or null)
      ]
    );

  candidateUplinkNamesForWanGroup =
    wanGroupName:
    let
      groupKeys = lib.unique (
        lib.filter builtins.isString ([ wanGroupName ] ++ (upstreamNamesForWanGroup wanGroupName))
      );
    in
    lib.filter (
      uplinkName:
      let
        keys = uplinkMatchKeys uplinkName;
      in
      lib.any (key: builtins.elem key keys) groupKeys
    ) uplinkNames;
in
{
  inherit
    sourceKindForTarget
    logicalNodeIdentityForTarget
    wanGroupNameForTarget
    isOverlayTransportTarget
    uplinksRaw
    hostHasUplinks
    uplinkNames
    wanGroupNames
    wanTargetsForGroup
    upstreamNamesForWanGroup
    uplinkMatchKeys
    candidateUplinkNamesForWanGroup
    ;
}
