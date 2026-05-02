{
  lib,
  currentSite,
  common,
}:

let
  inherit (common) sortedStrings lastStringSegment;

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
in
{
  inherit transitAdjacencies adjacencyUnits adjacencyLinkName;

  adjacencyForPair =
    { a, b, linkNameMatches ? null }:
    let
      matches = lib.filter (
        adjacency:
        let
          units = adjacencyUnits adjacency;
        in
        builtins.length units == 2 && builtins.elem a units && builtins.elem b units
      ) transitAdjacencies;

      matchesByLink =
        if linkNameMatches == null then
          [ ]
        else
          lib.filter (
            adjacency:
            let
              ln = adjacencyLinkName adjacency;
            in
            ln != null && linkNameMatches ln
          ) matches;
    in
    if builtins.length matchesByLink == 1 then
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
}
