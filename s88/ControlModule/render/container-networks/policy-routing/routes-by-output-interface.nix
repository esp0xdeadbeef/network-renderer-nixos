{ mkRoute, routeOutputInterface }:

{
  interfaceName,
  rawRoutesForPolicyTable,
  sourceIfNames,
  tableId,
  tableForOutputIfName ? (_outputIfName: tableId),
}:
let
  rawPolicyRoutes = builtins.concatMap (
    sourceIfName:
    map (route: route // { _s88PolicySourceIfName = sourceIfName; }) (
      rawRoutesForPolicyTable tableId interfaceName sourceIfName
    )
  ) sourceIfNames;
in

let
  foldRouteSet = builtins.foldl' (
    routesAcc: rawRoute:
    let
      sourceIfName = rawRoute._s88PolicySourceIfName;
      outputIfName = routeOutputInterface sourceIfName rawRoute;
      outputTableId = tableForOutputIfName outputIfName;
      renderedRoute = mkRoute (
        (builtins.removeAttrs rawRoute [
          "_s88PolicySourceIfName"
          "_s88ForwardTargetDefault"
        ])
        // {

          table = outputTableId;
        }
      );
      annotatedRoute =
        if renderedRoute == null then
          null
        else
          renderedRoute
          // {
            _s88Multipath = rawRoute.multipath or null;
            _s88Table = outputTableId;
          };
    in
    if annotatedRoute == null then
      routesAcc
    else
      routesAcc
      // {
        ${outputIfName} = (routesAcc.${outputIfName} or [ ]) ++ [ annotatedRoute ];
      }
  ) { } rawPolicyRoutes;

  routeIdentity =
    route:
    builtins.toJSON (
      builtins.removeAttrs route [
        "_s88Multipath"
        "_s88Table"
      ]
    );
in
builtins.mapAttrs (
  _: routes:
  builtins.attrValues (
    builtins.listToAttrs (
      map (route: {
        name = routeIdentity route;
        value = route;
      }) routes
    )
  )
) foldRouteSet
