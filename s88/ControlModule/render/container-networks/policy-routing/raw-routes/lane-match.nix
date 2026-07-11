{ lib
, interfaces
, interfaceNames
, renderedInterfaceNames
,
}:
let
  interfaceLane =
    interfaceName:
    let
      key = lib.findFirst (name: renderedInterfaceNames.${name} == interfaceName) null interfaceNames;
    in
    if key == null then { } else (interfaces.${key}.backingRef or { }).lane or { };

  laneAccess = lane: lane.access or null;
  laneUplink = lane: lane.uplink or null;
  laneUplinks = lane: if builtins.isList (lane.uplinks or null) then lane.uplinks else [ ];
  uplinkMatches =
    targetUplink: routeLane:
    targetUplink == null
    || laneUplink routeLane == null
    || laneUplink routeLane == targetUplink
    || builtins.elem targetUplink (laneUplinks routeLane);
in
{
  routeMatchesInterfaceLane =
    interfaceName: route:
    let
      targetLane = interfaceLane interfaceName;
      routeLane = route.lane or { };
      targetAccess = laneAccess targetLane;
      routeAccess = laneAccess routeLane;
    in
    (targetAccess == null || routeAccess == targetAccess)
    && uplinkMatches (laneUplink targetLane) routeLane;
}
