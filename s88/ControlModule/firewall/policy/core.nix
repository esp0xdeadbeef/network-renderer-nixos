{
  lib,
  interfaceView ? null,
  forwardingIntent ? null,
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

  interfaceWanNames =
    if interfaceView != null && builtins.isAttrs interfaceView && interfaceView ? wanNames then
      interfaceView.wanNames
    else
      [ ];

  interfaceLanNames =
    if interfaceView != null && builtins.isAttrs interfaceView && interfaceView ? lanNames then
      interfaceView.lanNames
    else
      [ ];

  wanNames = sortedStrings (interfaceWanNames ++ wanIfs);
  lanNames = sortedStrings (interfaceLanNames ++ lanIfs);

  adapterNames = sortedStrings (wanNames ++ lanNames);

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

  fallbackNatEnabled = wanNames != [ ] && (uplinkNames == [ ] || lib.any uplinkHasIpv4 uplinkNames);

  useExplicitForwarding =
    forwardingIntent != null
    && builtins.isAttrs forwardingIntent
    && (forwardingIntent.authoritativeCoreForwarding or false);

  useExplicitNat =
    forwardingIntent != null
    && builtins.isAttrs forwardingIntent
    && (forwardingIntent.authoritativeCoreNat or false);

  forwardPairs =
    if useExplicitForwarding then
      forwardingIntent.coreForwardPairs or [ ]
    else
      lib.optionals (lanNames != [ ] && wanNames != [ ]) [
        {
          "in" = lanNames;
          "out" = wanNames;
          action = "accept";
          comment = "core-lan-to-wan";
        }
      ];

  natInterfaces =
    if useExplicitNat then
      forwardingIntent.coreNatInterfaces or [ ]
    else if fallbackNatEnabled then
      wanNames
    else
      [ ];

  clampMssInterfaces =
    if useExplicitNat || useExplicitForwarding then
      forwardingIntent.coreClampMssInterfaces or [ ]
    else
      wanNames;

  inputRules = [
    ''
      icmpv6 type { nd-neighbor-solicit, nd-neighbor-advert, nd-router-solicit, nd-router-advert } accept comment "allow-ipv6-nd-ra"
    ''
  ];

  _validateCoreAdapterCount =
    if builtins.length adapterNames == 1 then
      throw ''
        s88/ControlModule/firewall/policy/core.nix: core role requires at least two adapters

        unitName:
        ${builtins.toJSON unitName}

        adapters:
        ${builtins.toJSON adapterNames}
      ''
    else
      true;
in
if wanNames == [ ] && lanNames == [ ] then
  null
else
  builtins.seq _validateCoreAdapterCount {
    tableName = "router";
    inputPolicy = "drop";
    outputPolicy = "accept";
    forwardPolicy = "drop";
    inherit
      inputRules
      forwardPairs
      natInterfaces
      clampMssInterfaces
      ;
  }
