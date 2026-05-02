{
  lib,
  forwardingIntent,
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

  uplinkNames = if builtins.isAttrs uplinks then lib.sort builtins.lessThan (builtins.attrNames uplinks) else [ ];

  uplinkHasIpv4 =
    uplinkName:
    let
      uplink = uplinks.${uplinkName};
      ipv4 = if uplink ? ipv4 && builtins.isAttrs uplink.ipv4 then uplink.ipv4 else null;
    in
    if ipv4 == null then true else if ipv4 ? enable then (ipv4.enable or false) else true;
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

  natInterfaces = if useExplicitNat then forwardingIntent.coreNatInterfaces or [ ] else [ ];

  clampMssInterfaces =
    if useExplicitNat || useExplicitForwarding then forwardingIntent.coreClampMssInterfaces or [ ] else wanNames;

  fallbackNatEnabled = wanNames != [ ] && (uplinkNames == [ ] || lib.any uplinkHasIpv4 uplinkNames);
  coreInputOverlayNames = overlayIngressNames;
  inherit adapterNames;
}
