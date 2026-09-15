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
builtins.foldl' (
  routesAcc: rawRoute:
  let
    sourceIfName = rawRoute._s88PolicySourceIfName;
    outputIfName = routeOutputInterface sourceIfName rawRoute;
    outputTableId = tableForOutputIfName outputIfName;
    forwardTargetDefault = rawRoute._s88ForwardTargetDefault or false;
    _is0 =
      builtins.isAttrs rawRoute
      && ((rawRoute.dst or "") == "0.0.0.0/0" || (rawRoute.dst or "") == "::/0");
    _t = builtins.trace (
      "RBOI dst="
      + (toString (rawRoute.dst or "?"))
      + " src="
      + sourceIfName
      + " out="
      + outputIfName
      + " ftd="
      + builtins.toJSON forwardTargetDefault
      + " table="
      + builtins.toJSON (rawRoute.table or null)
      + " outputTable="
      + builtins.toJSON outputTableId
    ) true;
    renderedRoute = builtins.seq _t (
      mkRoute (
        (builtins.removeAttrs rawRoute [
          "_s88PolicySourceIfName"
          "_s88ForwardTargetDefault"
        ])
        // {
          table = if forwardTargetDefault then rawRoute.table or tableId else outputTableId;
        }
      )
    );
    annotatedRoute =
      if renderedRoute == null then
        null
      else
        renderedRoute
        // {
          _s88Multipath = rawRoute.multipath or null;
          _s88Table = if forwardTargetDefault then rawRoute.table or tableId else outputTableId;
        };
  in
  if annotatedRoute == null then
    routesAcc
  else
    routesAcc
    // {
      ${outputIfName} = (routesAcc.${outputIfName} or [ ]) ++ [ annotatedRoute ];
    }
) { } rawPolicyRoutes
