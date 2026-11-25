{
  lib,
  forwardingIntent,
  interfaceView ? { },
  uplinks,
  wanNames,
  lanNames,
  forwardEgressNames,
  overlayIngressNames,
  adapterNames,
}:

let
  useExplicitForwarding =
    forwardingIntent != null
    && builtins.isAttrs forwardingIntent
    && (forwardingIntent.authoritativeCoreForwarding or false);

  useExplicitNat =
    forwardingIntent != null
    && builtins.isAttrs forwardingIntent
    && (forwardingIntent.authoritativeCoreNat or false);

  interfaceMap =
    if builtins.isAttrs (interfaceView.interfaceMap or null) then interfaceView.interfaceMap else { };

  resolveName =
    name:
    let
      entry = interfaceMap.${name} or null;
      resolved = if builtins.isAttrs entry then entry.name or null else null;
    in
    if builtins.isString resolved && resolved != "" then resolved else name;

  resolveNames =
    names:
    map resolveName (
      if names == null then
        [ ]
      else if builtins.isString names then
        [ names ]
      else if builtins.isList names then
        lib.filter builtins.isString names
      else
        [ ]
    );

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
in
{
  forwardPairs =
    if useExplicitForwarding then
      forwardingIntent.coreForwardPairs or [ ]
    else
      lib.optionals (lanNames != [ ] && forwardEgressNames != [ ]) [
        {
          "in" = lanNames;
          "out" = forwardEgressNames;
          action = "accept";
          comment = "core-lan-to-egress";
        }
      ];

  natInterfaces =
    if useExplicitNat then
      resolveNames (
        if forwardingIntent ? coreNat4Interfaces then
          forwardingIntent.coreNat4Interfaces
        else
          forwardingIntent.coreNatInterfaces or [ ]
      )
    else if fallbackNatEnabled then
      wanNames
    else
      [ ];
  nat4SourcePrefixes = if useExplicitNat then forwardingIntent.coreNat4SourcePrefixes or [ ] else [ ];
  nat6Interfaces =
    if useExplicitNat then
      resolveNames (forwardingIntent.coreNat6Interfaces or [ ])
    else if fallbackNatEnabled then
      wanNames
    else
      [ ];
  nat6SourcePrefixes = if useExplicitNat then forwardingIntent.coreNat6SourcePrefixes or [ ] else [ ];

  clampMssInterfaces =
    if useExplicitNat || useExplicitForwarding then
      resolveNames (forwardingIntent.coreClampMssInterfaces or [ ])
    else
      wanNames;

  coreInputOverlayNames = overlayIngressNames;
  inherit adapterNames;
}
