{ lib
, interfaceView
, currentSite
, currentNodeName
, interfaceEntries
, transitAdjacencies
, adjacencyUnits
, adjacencyLinkName
, adjacencyLaneUplinkMatches
, interfaceLaneUplinkMatches
, interfaceNameForLink
, interfaceNameForLinkMatching
, sourceKindOf
, common
,
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
      lib.filter
        (
          adjacency:
          let
            units = adjacencyUnits adjacency;
          in
          builtins.length units == 2
          && builtins.elem currentNodeName units
          && builtins.elem upstreamSelectorNodeName units
        )
        transitAdjacencies
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

  upstreamInterfacesForUplink =
    uplinkName:
    let
      matches = lib.filter
        (
          adjacency: adjacencyLaneUplinkMatches uplinkName adjacency
        )
        upstreamMatches;
      linkNames = lib.filter (ln: ln != null) (map adjacencyLinkName matches);
      laneTaggedInterfaces = lib.filter (name: name != null) (
        map
          (
            entry:
            let
              linkName =
                if builtins.isAttrs (entry.backingRef or null) && builtins.isString (entry.backingRef.name or null) then
                  entry.backingRef.name
                else if
                  entry ? iface
                  && builtins.isAttrs entry.iface
                  && entry.iface ? backingRef
                  && builtins.isAttrs entry.iface.backingRef
                  && builtins.isString (entry.iface.backingRef.name or null)
                then
                  entry.iface.backingRef.name
                else if builtins.isString (entry.name or null) then
                  entry.name
                else
                  null;
            in
            if linkName == null || !(interfaceLaneUplinkMatches uplinkName entry) then
              null
            else
              let
                matched = interfaceNameForLinkMatching linkName (interfaceLaneUplinkMatches uplinkName);
              in
              if matched != null then matched else interfaceNameForLink linkName
          )
          interfaceEntries
      );
      adjacencyInterfaces =
        lib.filter (n: n != null) (
          map
            (
              linkName:
              let
                matched = interfaceNameForLinkMatching linkName (interfaceLaneUplinkMatches uplinkName);
              in
              if matched != null then matched else interfaceNameForLink linkName
            )
            linkNames
        );
    in
    sortedStrings (laneTaggedInterfaces ++ adjacencyInterfaces);

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
      lib.filter
        (
          entry:
          builtins.elem (entry.name or null) upstreamInterfaceNames
          && builtins.any routeIsDefault (routesOf entry)
        )
        interfaceEntries
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
      lib.filter
        (
          entry:
          let
            sourceKind = sourceKindOf entry;
          in
          sourceKind != "wan" && sourceKind != "p2p"
        )
        interfaceEntries
    )
  );
}
