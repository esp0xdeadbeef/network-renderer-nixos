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
    renderedRoute = mkRoute (
      (builtins.removeAttrs rawRoute [
        "_s88PolicySourceIfName"
        "_s88ForwardTargetDefault"
      ])
      // {
        table = if forwardTargetDefault then rawRoute.table or tableId else outputTableId;
      }
    );
  in
  if renderedRoute == null then
    routesAcc
  else
    routesAcc
    // {
      ${outputIfName} = (routesAcc.${outputIfName} or [ ]) ++ [ renderedRoute ];
    }
) { } rawPolicyRoutes
