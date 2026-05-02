{ lib, roles, normalizedExplicitForwardPairs, nodeForwarding, nodeForwardingEnabled, natEnabled }:

let
  maybePair =
    inIfs: outIfs: comment:
    if inIfs != [ ] && outIfs != [ ] then { "in" = inIfs; "out" = outIfs; action = "accept"; inherit comment; } else null;

  accessForwardPairs =
    if normalizedExplicitForwardPairs != [ ] then
      normalizedExplicitForwardPairs
    else
      lib.filter (pair: pair != null) [
        (maybePair roles.resolvedLocalAdapterNames roles.resolvedAccessUplinkNames "access-local-to-uplink")
        (maybePair roles.resolvedAccessUplinkNames roles.resolvedLocalAdapterNames "access-uplink-to-local")
      ];

  baseCoreForwardPairs =
    if normalizedExplicitForwardPairs != [ ] then
      normalizedExplicitForwardPairs
    else
      lib.filter (pair: pair != null) [
        (maybePair roles.resolvedLanNames roles.resolvedWanNames "core-lan-to-wan")
      ];

  overlayCoreForwardPairs = lib.filter (pair: pair != null) [
    (maybePair roles.resolvedLanNames roles.overlayInterfaceNames "core-lan-to-overlay")
    (maybePair roles.overlayInterfaceNames roles.resolvedLanNames "core-overlay-to-lan")
  ];

  hasExplicitSelectorForwarding =
    (nodeForwarding.mode or null) == "explicit-selector-forwarding"
    && nodeForwarding ? rules
    && builtins.isList nodeForwarding.rules;

  coreNatInterfaces =
    if natEnabled == false then
      [ ]
    else if roles.explicitNatInterfaces != [ ] then
      roles.explicitNatInterfaces
    else if natEnabled == true && roles.explicitExitEligibleNames != [ ] then
      roles.explicitExitEligibleNames
    else if natEnabled == true then
      roles.resolvedWanNames
    else
      [ ];
in
{
  inherit accessForwardPairs coreNatInterfaces;
  coreForwardPairs = baseCoreForwardPairs ++ overlayCoreForwardPairs;
  upstreamSelectorForwardPairs = if normalizedExplicitForwardPairs != [ ] then normalizedExplicitForwardPairs else [ ];
  accessClampMssInterfaces =
    if roles.explicitClampMssInterfaces != [ ] then roles.explicitClampMssInterfaces else if roles.resolvedTransitNames == [ ] then roles.resolvedWanNames else [ ];
  coreClampMssInterfaces =
    if roles.explicitClampMssInterfaces != [ ] then roles.explicitClampMssInterfaces else if coreNatInterfaces != [ ] then coreNatInterfaces else [ ];
  authoritativeAccessForwarding =
    normalizedExplicitForwardPairs != [ ] || nodeForwardingEnabled == false || (roles.explicitLocalAdapterNames != [ ] && roles.explicitUplinkNames != [ ]);
  authoritativeCoreForwarding =
    normalizedExplicitForwardPairs != [ ] || nodeForwardingEnabled == false || (roles.explicitLocalAdapterNames != [ ] && roles.explicitUplinkNames != [ ]);
  authoritativeCoreNat =
    roles.explicitNatInterfaces != [ ] || natEnabled == false || (natEnabled == true && roles.explicitExitEligibleNames != [ ]);
  authoritativeUpstreamSelectorForwarding =
    normalizedExplicitForwardPairs != [ ] || nodeForwardingEnabled == false || hasExplicitSelectorForwarding;
}
