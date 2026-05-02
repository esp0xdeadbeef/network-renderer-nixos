{
  lib,
  interfaceView,
  currentSite,
  currentNodeName,
  interfaceEntries,
  transitAdjacencies,
  adjacencyUnits,
  adjacencyLinkName,
  interfaceNameForLink,
  sourceKindOf,
  common,
}:

let
  inherit (common) sortedStrings entryFieldOr;

  upstreamSelectorNodeName =
    if
      currentSite ? upstreamSelectorNodeName
      && builtins.isString currentSite.upstreamSelectorNodeName
      && currentSite.upstreamSelectorNodeName != ""
    then
      currentSite.upstreamSelectorNodeName
    else
      null;

  explicitWanNames =
    if interfaceView != null && builtins.isAttrs interfaceView && interfaceView ? wanNames then
      sortedStrings interfaceView.wanNames
    else
      [ ];

  upstreamMatches =
    if currentNodeName != null && upstreamSelectorNodeName != null then
      lib.filter (
        adjacency:
        let
          units = adjacencyUnits adjacency;
        in
        builtins.length units == 2
        && builtins.elem currentNodeName units
        && builtins.elem upstreamSelectorNodeName units
      ) transitAdjacencies
    else
      [ ];

  upstreamInterfaceNames =
    let
      linkNames = lib.filter (ln: ln != null) (map adjacencyLinkName upstreamMatches);
      ifNames = lib.filter (n: n != null) (map interfaceNameForLink linkNames);
    in
    if ifNames != [ ] then
      sortedStrings ifNames
    else if explicitWanNames != [ ] then
      [ (builtins.head explicitWanNames) ]
    else
      [ ];

  upstreamAdjacencyLinkNames = lib.filter (ln: ln != null) (map adjacencyLinkName upstreamMatches);

  upstreamInterfacesForUplink =
    uplinkName:
    let
      candidates =
        if !builtins.isString uplinkName || uplinkName == "" then
          [ ]
        else
          let
            raw = [
              uplinkName
              "uplink-${uplinkName}"
            ];
          in
          if lib.hasPrefix "uplink-" uplinkName then
            raw ++ [ (lib.removePrefix "uplink-" uplinkName) ]
          else
            raw;

      matches = lib.filter (
        ln:
        lib.any (
          candidate: builtins.isString candidate && candidate != "" && lib.hasInfix candidate ln
        ) candidates
      ) upstreamAdjacencyLinkNames;
    in
    sortedStrings (lib.filter (n: n != null) (map interfaceNameForLink matches));

  routesOf =
    entry:
    let
      routes = entryFieldOr entry "routes" null;
    in
    if builtins.isAttrs routes then
      lib.concatLists (builtins.attrValues routes)
    else if builtins.isList routes then
      routes
    else
      [ ];

  routeIsDefault =
    route:
    builtins.isAttrs route && ((route.dst or null) == "0.0.0.0/0" || (route.dst or null) == "::/0");

  exitUpstreamInterfaceNames = sortedStrings (
    map (entry: entry.name) (
      lib.filter (
        entry:
        builtins.elem (entry.name or null) upstreamInterfaceNames
        && builtins.any routeIsDefault (routesOf entry)
      ) interfaceEntries
    )
  );
in
rec {
  inherit
    upstreamSelectorNodeName
    explicitWanNames
    upstreamInterfaceNames
    upstreamInterfacesForUplink
    ;

  wanEndpointNames =
    if explicitWanNames != [ ] then
      explicitWanNames
    else
      let
        wanUplinkNames = upstreamInterfacesForUplink "wan";
      in
      if wanUplinkNames != [ ] then
        wanUplinkNames
      else if exitUpstreamInterfaceNames != [ ] then
        exitUpstreamInterfaceNames
      else
        upstreamInterfaceNames;

  wanNames = explicitWanNames;

  p2pNames = sortedStrings (
    map (entry: entry.name) (lib.filter (entry: sourceKindOf entry == "p2p") interfaceEntries)
  );

  localAdapterNames = sortedStrings (
    map (entry: entry.name) (
      lib.filter (
        entry:
        let
          sourceKind = sourceKindOf entry;
        in
        sourceKind != "wan" && sourceKind != "p2p"
      ) interfaceEntries
    )
  );
}
