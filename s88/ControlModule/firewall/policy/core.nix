{
  lib,
  interfaceView,
  uplinks ? { },
  ...
}:

let
  wanEntries = interfaceView.wanEntries or [ ];
  wanNames = interfaceView.wanNames or [ ];
  lanNames = interfaceView.lanNames or [ ];

  uplinkForEntry =
    entry:
    if
      entry ? assignedUplinkName
      && builtins.isString entry.assignedUplinkName
      && builtins.hasAttr entry.assignedUplinkName uplinks
    then
      uplinks.${entry.assignedUplinkName}
    else
      { };

  masqueradeEnabled =
    uplink:
    (uplink.masquerade or false)
    || (lib.attrByPath [ "nat" "enable" ] false uplink)
    || (lib.attrByPath [ "nat" "masquerade" ] false uplink)
    || (lib.attrByPath [ "ipv4" "masquerade" ] false uplink);

  mssClampEnabled =
    uplink:
    if uplink ? mssClamp then
      uplink.mssClamp
    else if uplink ? tcpMssClamp then
      uplink.tcpMssClamp
    else if lib.hasAttrByPath [ "tcp" "mssClamp" ] uplink then
      lib.attrByPath [ "tcp" "mssClamp" ] false uplink
    else if lib.hasAttrByPath [ "tcpMssClamp" "enable" ] uplink then
      lib.attrByPath [ "tcpMssClamp" "enable" ] false uplink
    else
      true;

  natInterfaces = map (entry: entry.name) (
    lib.filter (entry: masqueradeEnabled (uplinkForEntry entry)) wanEntries
  );

  clampMssInterfaces = map (entry: entry.name) (
    lib.filter (entry: mssClampEnabled (uplinkForEntry entry)) wanEntries
  );
in
if wanNames == [ ] || lanNames == [ ] then
  null
else
  {
    tableName = "router";
    inputPolicy = "accept";
    outputPolicy = "accept";
    forwardPolicy = "drop";

    forwardPairs = [
      {
        "in" = lanNames;
        "out" = wanNames;
        action = "accept";
        comment = "core-lan-to-wan";
      }
    ];

    natInterfaces = natInterfaces;
    clampMssInterfaces = clampMssInterfaces;
  }
