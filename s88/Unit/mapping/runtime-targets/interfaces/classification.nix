{ common }:

{ sourceKind, backingRef }:
let
  lane = common.attrsOrEmpty ((common.attrsOrEmpty backingRef).lane or null);
  laneKind = lane.kind or null;
in
{
  edgeFacing = sourceKind == "p2p" && laneKind == "access-edge";
  fabricFacing = sourceKind == "p2p" && laneKind == "access";
  exitFacing = sourceKind == "p2p" && laneKind == "access-uplink";
  coreFacing = sourceKind == "p2p" && laneKind == "uplink";
  overlay = sourceKind == "overlay" || (backingRef.kind or null) == "overlay";
  coreTransit = sourceKind == "p2p" && laneKind == "uplink";
}
