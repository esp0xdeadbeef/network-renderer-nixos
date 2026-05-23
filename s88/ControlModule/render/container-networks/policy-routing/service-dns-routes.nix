{ lib, routeHelpers }:

let
  routeDestinationKey = route: "${toString (route.table or "main")}|${route.dst or ""}";
in
{
  prefer =
    routes:
    lib.concatMap (
      group:
      let
        serviceRoutes = lib.filter routeHelpers.isServiceDnsReachabilityRoute group;
      in
      if serviceRoutes == [ ] then group else serviceRoutes
    ) (builtins.attrValues (builtins.groupBy routeDestinationKey routes));
}
