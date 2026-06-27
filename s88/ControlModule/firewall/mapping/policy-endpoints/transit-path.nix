{ lib
, currentNodeName
, interfaceNameForLink
, interfaceNameForLinkMatching
, interfaceLaneAccessMatches
, transitAdjacencies
, adjacencyUnits
, adjacencyLinkName
, adjacenciesForPair
, adjacencyLaneAccessMatches
, common
,
}:

let
  inherit (common) sortedStrings;

  transitEdges = lib.concatMap
    (
      adjacency:
      let
        units = adjacencyUnits adjacency;
      in
      if builtins.length units == 2 then
        let
          a = builtins.elemAt units 0;
          b = builtins.elemAt units 1;
        in
        [
          { from = a; to = b; }
          { from = b; to = a; }
        ]
      else
        [ ]
    )
    transitAdjacencies;

  neighborsOf =
    unit: sortedStrings (map (edge: edge.to) (lib.filter (edge: edge.from == unit) transitEdges));

  lastElem =
    list:
    let
      n = builtins.length list;
    in
    if n == 0 then null else builtins.elemAt list (n - 1);

  findPath =
    { start, goal }:
    let
      go =
        visited: frontier:
        if frontier == [ ] then
          null
        else
          let
            path = builtins.head frontier;
            rest = builtins.tail frontier;
            node = lastElem path;
          in
          if node == null then
            null
          else if node == goal then
            path
          else
            let
              candidates = neighborsOf node;
              nexts = lib.filter (n: !(builtins.elem n visited)) candidates;
            in
            go (visited ++ nexts) (rest ++ (map (n: path ++ [ n ]) nexts));
    in
    if start == null || goal == null then null else go [ start ] [ [ start ] ];
in
{
  inherit findPath;

  firstHopInterfacesToUnit =
    targetUnit:
    if currentNodeName == null || targetUnit == null then
      [ ]
    else
      let
        path = findPath { start = currentNodeName; goal = targetUnit; };
        hop = if path != null && builtins.length path >= 2 then builtins.elemAt path 1 else null;
        matchingAdjacencies =
          if hop != null then
            adjacenciesForPair
              {
                a = currentNodeName;
                b = hop;
              }
          else
            [ ];
        matchedLinkNames = lib.filter (ln: ln != null) (
          map
            (
              adjacency:
              let
                linkName = adjacencyLinkName adjacency;
              in
              if
                linkName != null
                && interfaceNameForLinkMatching linkName (interfaceLaneAccessMatches targetUnit) != null
              then
                linkName
              else
                null
            )
            matchingAdjacencies
        );
        fallbackLinkNames = lib.filter (ln: ln != null) (map adjacencyLinkName matchingAdjacencies);
        interfaceForMatchedLink =
          linkName:
          let
            matched = interfaceNameForLinkMatching linkName (interfaceLaneAccessMatches targetUnit);
          in
          if matched != null then matched else interfaceNameForLink linkName;
        interfaceForFallbackLink = linkName: interfaceNameForLink linkName;
      in
      sortedStrings (
        lib.filter (name: name != null) (
          if matchedLinkNames != [ ] then
            map interfaceForMatchedLink matchedLinkNames
          else
            map interfaceForFallbackLink fallbackLinkNames
        )
      );

  firstHopInterfaceToUnit =
    targetUnit:
    if currentNodeName == null || targetUnit == null then
      null
    else
      let
        path = findPath { start = currentNodeName; goal = targetUnit; };
        hop = if path != null && builtins.length path >= 2 then builtins.elemAt path 1 else null;
        matchingAdjacencies =
          if hop != null then
            adjacenciesForPair
              {
                a = currentNodeName;
                b = hop;
              }
          else
            [ ];
        matchedLinkNames = lib.filter (ln: ln != null) (
          map
            (
              adjacency:
              let
                linkName = adjacencyLinkName adjacency;
              in
              if
                linkName != null
                && interfaceNameForLinkMatching linkName (interfaceLaneAccessMatches targetUnit) != null
              then
                linkName
              else
                null
            )
            matchingAdjacencies
        );
        fallbackLinkNames = lib.filter (ln: ln != null) (map adjacencyLinkName matchingAdjacencies);
        linkName =
          if builtins.length matchedLinkNames == 1 then
            builtins.head matchedLinkNames
          else if builtins.length matchedLinkNames > 1 then
            throw ''
              s88/ControlModule/firewall/mapping/policy-endpoints.nix: interface lane metadata matched multiple first-hop adjacencies for '${currentNodeName}' toward '${targetUnit}'

              matches:
              ${builtins.toJSON matchedLinkNames}
            ''
          else if builtins.length fallbackLinkNames == 1 then
            builtins.head fallbackLinkNames
          else if fallbackLinkNames == [ ] then
            null
          else
            throw ''
              s88/ControlModule/firewall/mapping/policy-endpoints.nix: multiple first-hop adjacencies matched '${currentNodeName}' toward '${targetUnit}' and CPM interface lane metadata did not disambiguate them

              matches:
              ${builtins.toJSON fallbackLinkNames}
            '';
      in
      if linkName != null then
        let
          matched = interfaceNameForLinkMatching linkName (interfaceLaneAccessMatches targetUnit);
        in
        if matched != null then matched else interfaceNameForLink linkName
      else
        null;
}
