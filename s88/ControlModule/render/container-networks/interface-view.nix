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

  laneForInterfaceKey =
    ifName:
    let
      iface = interfaces.${ifName} or { };
      backingRef = backingRefForInterface iface;
    in
    if builtins.isString (backingRef.lane or null) && backingRef.lane != "" then
      backingRef.lane
    else
      null;

  uplinkNamesFromLane =
    lane:
    let
      coreMatch = if builtins.isString lane then builtins.match "uplink::(.+)" lane else null;
      accessMatch =
        if builtins.isString lane then builtins.match "access::.+::uplink::(.+)" lane else null;
    in
    if coreMatch != null then
      [ (builtins.elemAt coreMatch 0) ]
    else if accessMatch != null then
      [ (builtins.elemAt accessMatch 0) ]
    else
      [ ];

  uplinkNamesForRenderedName =
    name:
    let
      ifName = interfaceKeyForRenderedName name;
      iface = if ifName == null then { } else interfaces.${ifName} or { };
      backingRef = backingRefForInterface iface;
      explicitUplinks =
        if builtins.isList (backingRef.uplinks or null) then
          lib.filter builtins.isString backingRef.uplinks
        else
          [ ];
    in
    lib.unique (explicitUplinks ++ uplinkNamesFromLane (laneForInterfaceKey ifName));
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
