{
  lib,
  interfaces,
  common,
}:

let
  inherit (common) sortedAttrNames interfaceNameFor;

  interfaceNames = sortedAttrNames interfaces;

  renderedInterfaceNames = builtins.listToAttrs (
    map (ifName: {
      name = ifName;
      value = interfaceNameFor interfaces.${ifName};
    }) interfaceNames
  );

  interfaceKeyForRenderedName =
    name:
    let
      matches = lib.filter (
        ifName: ifName == name || renderedInterfaceNames.${ifName} == name
      ) interfaceNames;
    in
    if matches == [ ] then null else builtins.head matches;

  backingRefForInterface =
    iface:
    if iface ? backingRef && builtins.isAttrs iface.backingRef then
      iface.backingRef
    else if
      iface ? connectivity
      && builtins.isAttrs iface.connectivity
      && iface.connectivity ? backingRef
      && builtins.isAttrs iface.connectivity.backingRef
    then
      iface.connectivity.backingRef
    else
      { };

  uplinkNamesForRenderedName =
    name:
    let
      ifName = interfaceKeyForRenderedName name;
      iface = if ifName == null then { } else interfaces.${ifName} or { };
      backingRef = backingRefForInterface iface;
      lane = backingRef.lane or { };
      explicitUplinks =
        if builtins.isList (backingRef.uplinks or null) then
          lib.filter builtins.isString backingRef.uplinks
        else
          [ ];
      laneUplinks =
        if builtins.isAttrs lane && builtins.isList (lane.uplinks or null) then
          lib.filter builtins.isString lane.uplinks
        else
          [ ];
    in
    lib.unique (explicitUplinks ++ laneUplinks);
in
{
  inherit
    interfaces
    interfaceNames
    renderedInterfaceNames
    interfaceKeyForRenderedName
    ;

  upstreamLanesMatch =
    targetName: sourceName:
    let
      targetUplinks = uplinkNamesForRenderedName targetName;
      sourceUplinks = uplinkNamesForRenderedName sourceName;
    in
    lib.any (uplink: builtins.elem uplink sourceUplinks) targetUplinks;
}
