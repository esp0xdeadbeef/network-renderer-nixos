{ lib
, currentSite
, common
,
}:

let
  inherit (common) sortedStrings lastStringSegment;

  attrsOrEmpty = value: if builtins.isAttrs value then value else { };

  transitAdjacencies =
    if
      currentSite ? transit
      && builtins.isAttrs currentSite.transit
      && currentSite.transit ? adjacencies
      && builtins.isList currentSite.transit.adjacencies
    then
      lib.filter builtins.isAttrs currentSite.transit.adjacencies
    else
      [ ];

  adjacencyUnits =
    adjacency:
    sortedStrings (
      map
        (
          endpoint:
          if builtins.isAttrs endpoint && endpoint ? unit && builtins.isString endpoint.unit then
            endpoint.unit
          else
            null
        )
        (if adjacency ? endpoints && builtins.isList adjacency.endpoints then adjacency.endpoints else [ ])
    );

  adjacencyLinkName =
    adjacency:
    if adjacency ? link && builtins.isString adjacency.link then
      adjacency.link
    else if adjacency ? name && builtins.isString adjacency.name then
      adjacency.name
    else if adjacency ? id && builtins.isString adjacency.id then
      lastStringSegment "::" adjacency.id
    else
      null;

  adjacencyLaneAccessMatches =
    targetUnit: adjacency:
    let
      lane = attrsOrEmpty (adjacency.lane or null);
      laneMeta = attrsOrEmpty (adjacency.laneMeta or null);
    in
    builtins.isString targetUnit
    && targetUnit != ""
    && ((lane.access or null) == targetUnit || (laneMeta.access or null) == targetUnit);

  adjacencyLaneUplinkMatches =
    uplinkName: adjacency:
    let
      lane = attrsOrEmpty (adjacency.lane or null);
      laneMeta = attrsOrEmpty (adjacency.laneMeta or null);
      uplinks =
        sortedStrings (
          (if builtins.isList (adjacency.uplinks or null) then adjacency.uplinks else [ ])
          ++ (if builtins.isList (lane.uplinks or null) then lane.uplinks else [ ])
          ++ (if builtins.isList (laneMeta.uplinks or null) then laneMeta.uplinks else [ ])
          ++ [ (lane.uplink or null) (laneMeta.uplink or null) ]
        );
    in
    builtins.isString uplinkName && uplinkName != "" && builtins.elem uplinkName uplinks;

  adjacenciesForPair =
    { a, b }:
    lib.filter
      (
        adjacency:
        let
          units = adjacencyUnits adjacency;
        in
        builtins.length units == 2 && builtins.elem a units && builtins.elem b units
      )
      transitAdjacencies;

  adjacencyForPair =
    { a, b, linkNameMatches ? null, adjacencyMatches ? null }:
    let
      matches = adjacenciesForPair { inherit a b; };

      matchesByLink =
        if linkNameMatches == null then
          [ ]
        else
          lib.filter
            (
              adjacency:
              let
                ln = adjacencyLinkName adjacency;
              in
              ln != null && linkNameMatches ln
            )
            matches;
      matchesByAdjacency =
        if adjacencyMatches == null then
          [ ]
        else
          lib.filter adjacencyMatches matches;
    in
    if builtins.length matchesByAdjacency == 1 then
      builtins.head matchesByAdjacency
    else if builtins.length matchesByAdjacency > 1 then
      throw ''
        s88/ControlModule/firewall/mapping/policy-endpoints.nix: lane metadata selector matched multiple transit adjacencies for '${a}' and '${b}'

        matches:
        ${builtins.toJSON (map adjacencyLinkName matchesByAdjacency)}
      ''
    else if builtins.length matchesByLink == 1 then
      builtins.head matchesByLink
    else if builtins.length matchesByLink > 1 then
      throw ''
        s88/ControlModule/firewall/mapping/policy-endpoints.nix: lane selector matched multiple transit adjacencies for '${a}' and '${b}'

        matches:
        ${builtins.toJSON (map adjacencyLinkName matchesByLink)}
      ''
    else if builtins.length matches == 1 then
      builtins.head matches
    else if matches == [ ] then
      null
    else
      throw ''
        s88/ControlModule/firewall/mapping/policy-endpoints.nix: multiple transit adjacencies matched '${a}' and '${b}'

        matches:
        ${builtins.toJSON (map adjacencyLinkName matches)}
      '';
in
{
  inherit
    adjacenciesForPair
    adjacencyForPair
    adjacencyLaneAccessMatches
    adjacencyLaneUplinkMatches
    adjacencyLinkName
    adjacencyUnits
    transitAdjacencies
    ;
}
