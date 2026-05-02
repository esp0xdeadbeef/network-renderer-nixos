{
  lib,
  currentNodeName,
  interfaceNameForLink,
  transitAdjacencies,
  adjacencyUnits,
  adjacencyLinkName,
  adjacencyForPair,
  common,
}:

let
  inherit (common) sortedStrings;

  transitEdges = lib.concatMap (
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
  ) transitAdjacencies;

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

  firstHopInterfaceToUnit =
    targetUnit:
    if currentNodeName == null || targetUnit == null then
      null
    else
      let
        path = findPath { start = currentNodeName; goal = targetUnit; };
        hop = if path != null && builtins.length path >= 2 then builtins.elemAt path 1 else null;
        adjacency =
          if hop != null then
            adjacencyForPair {
              a = currentNodeName;
              b = hop;
              linkNameMatches =
                if builtins.isString targetUnit && targetUnit != "" then
                  (ln: builtins.match ".*--access-${targetUnit}($|--).*" ln != null)
                else
                  null;
            }
          else
            null;
        linkName = if adjacency != null then adjacencyLinkName adjacency else null;
      in
      if linkName != null then interfaceNameForLink linkName else null;
}
