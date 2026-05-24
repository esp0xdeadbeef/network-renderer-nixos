{ lib
, interfaces
, interfaceNames
, renderedInterfaceNames
,
}:
let
  interfaceLaneAccess =
    interfaceName:
    let
      key = lib.findFirst (name: renderedInterfaceNames.${name} == interfaceName) null interfaceNames;
    in
    if key == null then null else ((interfaces.${key}.backingRef or { }).lane or { }).access or null;

  routeLaneAccess = route: ((route.lane or { }).access or null);
in
{
  routeMatchesInterfaceLane =
    interfaceName: route:
    let
      targetAccess = interfaceLaneAccess interfaceName;
      routeAccess = routeLaneAccess route;
    in
    targetAccess == null || routeAccess == targetAccess;
}
