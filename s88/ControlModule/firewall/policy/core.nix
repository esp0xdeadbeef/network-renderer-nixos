{
  lib,
  unitName ? null,
  runtimeTarget ? { },
  interfaces ? { },
  wanIfs ? [ ],
  lanIfs ? [ ],
  uplinks ? { },
  ...
}:

let
  sortedStrings =
    values:
    lib.sort builtins.lessThan (
      lib.unique (lib.filter (value: builtins.isString value && value != "") values)
    );

  wanNames = sortedStrings wanIfs;
  lanNames = sortedStrings lanIfs;

  uplinkNames =
    if builtins.isAttrs uplinks then lib.sort builtins.lessThan (builtins.attrNames uplinks) else [ ];

  uplinkHasIpv4 =
    uplinkName:
    let
      uplink = uplinks.${uplinkName};
      ipv4 = if uplink ? ipv4 && builtins.isAttrs uplink.ipv4 then uplink.ipv4 else null;
    in
    if ipv4 == null then
      true
    else if ipv4 ? enable then
      (ipv4.enable or false)
    else
      true;

  natEnabled = wanNames != [ ] && (uplinkNames == [ ] || lib.any uplinkHasIpv4 uplinkNames);

  forwardPairs = lib.optionals (lanNames != [ ] && wanNames != [ ]) [
    {
      iifname = lanNames;
      oifname = wanNames;
      action = "accept";
      comment = "core-lan-to-wan";
    }
  ];
in
if wanNames == [ ] && lanNames == [ ] then
  null
else
  {
    tableName = "router";
    inputPolicy = "accept";
    outputPolicy = "accept";
    forwardPolicy = "drop";
    inherit forwardPairs;
    natInterfaces = if natEnabled then wanNames else [ ];
    clampMssInterfaces = wanNames;
  }
