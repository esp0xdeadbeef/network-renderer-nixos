{ lib, routesByInterface }:

let

  flat = lib.concatLists (
    lib.mapAttrsToList (
      ifName: routes: map (route: route // { _s88MultipathSourceIf = ifName; }) routes
    ) routesByInterface
  );

  routeKey =
    route:
    "${toString (route.Table or "")}|${
      toString (route.Destination or "")
    }|${toString (route.Metric or "")}";

  grouped = lib.groupBy routeKey flat;

  mergedGroups = lib.concatMap (
    group:
    if builtins.length group < 2 then
      group
    else
      let
        head = builtins.head group;
        gateways = lib.unique (
          lib.filter (g: g != null && g != "") (map (route: route.Gateway or null) group)
        );
      in
      if builtins.length gateways < 2 then
        group
      else
        [
          (
            (builtins.removeAttrs head [ "Gateway" ])
            // {
              MultiPathRoute = lib.sort (a: b: a < b) gateways;
            }
          )
        ]
  ) (builtins.attrValues grouped);

  redistributed = builtins.foldl' (
    acc: route:
    let
      sourceIf = route._s88MultipathSourceIf;
      clean = builtins.removeAttrs route [ "_s88MultipathSourceIf" ];
    in
    acc // { ${sourceIf} = (acc.${sourceIf} or [ ]) ++ [ clean ]; }
  ) { } mergedGroups;
in
redistributed
