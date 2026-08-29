{
  lib,
  renderedInterfaceNames,
  routesByInterface,
}:

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

  isDefaultDestination =
    route:
    (route.Destination or "") == "0.0.0.0/0"
    || (route.Destination or "") == "::/0"
    || (route.Destination or "") == "0000:0000:0000:0000:0000:0000:0000:0000/0";

  grouped = lib.groupBy routeKey flat;

  mergedGroups = lib.concatMap (
    group:
    if builtins.length group < 2 || !(isDefaultDestination (builtins.head group)) then
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
        let

          multipathMembers = lib.sort (a: b: a < b) (
            map (
              route:
              "${route.Gateway}@${
                renderedInterfaceNames.${route._s88MultipathSourceIf} or route._s88MultipathSourceIf
              }"
            ) group
          );
        in
        [
          (
            (builtins.removeAttrs head [ "Gateway" ])
            // {
              MultiPathRoute = multipathMembers;
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
