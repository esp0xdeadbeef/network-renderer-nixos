{ lib, routeHelpers }:

let

  routeDestinationKey =
    route: "${toString (route.Table or route.table or "main")}|${route.Destination or route.dst or ""}";

  isServiceRoute =
    route:
    let
      kind = route._s88IntentKind or ((route.intent or { }).kind or null);
    in
    kind == "service-dns-reachability" || kind == "service-endpoint-reachability";

  prefer =
    routes:
    lib.concatMap (
      group:
      let
        serviceRoutes = lib.filter isServiceRoute group;
      in
      if serviceRoutes == [ ] then group else serviceRoutes
    ) (builtins.attrValues (builtins.groupBy routeDestinationKey routes));
in
{
  inherit prefer;

  preferAcrossInterfaces =
    routesByInterface:
    let
      allRoutes = builtins.concatLists (builtins.attrValues routesByInterface);
      preferredKeys = builtins.foldl' (
        acc: route: if isServiceRoute route then acc // { ${routeDestinationKey route} = true; } else acc
      ) { } allRoutes;
    in
    lib.mapAttrs (
      _: routes:
      lib.filter (
        route: !(builtins.hasAttr (routeDestinationKey route) preferredKeys) || isServiceRoute route
      ) routes
    ) routesByInterface;
}
