{ lib, roles, normalizedExplicitForwardPairs, nodeForwarding, nodeForwardingEnabled, natEnabled, nat4Enabled, nat6Enabled }:

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
    else if hasExplicitCoreForwarding then
      # Corrected CPM authority present but no admitted pair survived:
      # fail closed, never invent core-lan-to-wan from roles.
      [ ]
    else
      lib.filter (pair: pair != null) [
        (maybePair roles.resolvedLanNames roles.resolvedWanNames "core-lan-to-wan")
      ];

  coreLocalForwardNames = lib.subtractLists roles.overlayInterfaceNames roles.resolvedLanNames;

  overlayCoreForwardPairs = lib.filter (pair: pair != null) [
    (maybePair coreLocalForwardNames roles.overlayInterfaceNames "core-lan-to-overlay")
    (maybePair roles.overlayInterfaceNames coreLocalForwardNames "core-overlay-to-lan")
  ];

  hasExplicitSelectorForwarding =
    (nodeForwarding.mode or null) == "explicit-selector-forwarding"
    && nodeForwarding ? rules
    && builtins.isList nodeForwarding.rules;

  # FS-270-HDS-010-SDS-010-SMS-010: when the CPM hands off explicit core
  # forwarding authority, that authority is exhaustive for interface-pair
  # transit. A core node whose corrected CPM output denies a transit surface
  # (or every transit surface: rules == [ ]) must not recover forwarding for
  # it from role-derived core-lan-to-wan pair invention — that would
  # resurrect the denied public-to-internal bypass class (2026-07-15
  # ens3<->ppp0) from topology provenance. Faithful realization renders
  # exactly the CPM-authorized rules; fail-closed realization renders no
  # lan-to-wan pair beyond them.
  hasExplicitCoreForwarding =
    (nodeForwarding.mode or null) == "explicit-core-forwarding"
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

  nat4Active = if nat4Enabled == null then natEnabled else nat4Enabled;
  nat6Active = if nat6Enabled == null then false else nat6Enabled;

  coreNat4Interfaces =
    if nat4Active == false then
      [ ]
    else if roles.explicitNat4Interfaces != [ ] then
      roles.explicitNat4Interfaces
    else
      coreNatInterfaces;

  coreNat6Interfaces =
    if nat6Active == false then
      [ ]
    else if roles.explicitNat6Interfaces != [ ] then
      roles.explicitNat6Interfaces
    else
      coreNatInterfaces;
in
{
  inherit accessForwardPairs coreNatInterfaces coreNat4Interfaces coreNat6Interfaces;
  coreNat4SourcePrefixes = roles.explicitNat4SourcePrefixes;
  coreNat6SourcePrefixes = roles.explicitNat6SourcePrefixes;
  coreForwardPairs = baseCoreForwardPairs ++ overlayCoreForwardPairs;
  downstreamSelectorForwardPairs = if normalizedExplicitForwardPairs != [ ] then normalizedExplicitForwardPairs else [ ];
  upstreamSelectorForwardPairs = if normalizedExplicitForwardPairs != [ ] then normalizedExplicitForwardPairs else [ ];
  accessClampMssInterfaces =
    if roles.explicitClampMssInterfaces != [ ] then roles.explicitClampMssInterfaces else if roles.resolvedTransitNames == [ ] then roles.resolvedWanNames else [ ];
  coreClampMssInterfaces =
    if roles.explicitClampMssInterfaces != [ ] then roles.explicitClampMssInterfaces else if coreNatInterfaces != [ ] then coreNatInterfaces else [ ];
  authoritativeAccessForwarding =
    normalizedExplicitForwardPairs != [ ] || nodeForwardingEnabled == false || (roles.explicitLocalAdapterNames != [ ] && roles.explicitUplinkNames != [ ]);
  authoritativeCoreForwarding =
    normalizedExplicitForwardPairs != [ ]
    || hasExplicitCoreForwarding
    || overlayCoreForwardPairs != [ ]
    || nodeForwardingEnabled == false
    || (roles.explicitLocalAdapterNames != [ ] && roles.explicitUplinkNames != [ ]);
  authoritativeCoreNat =
    roles.explicitNatInterfaces != [ ]
    || roles.explicitNat4Interfaces != [ ]
    || roles.explicitNat6Interfaces != [ ]
    || natEnabled == false
    || (natEnabled == true && roles.explicitExitEligibleNames != [ ]);
  authoritativeDownstreamSelectorForwarding =
    normalizedExplicitForwardPairs != [ ] || nodeForwardingEnabled == false || hasExplicitSelectorForwarding;
  authoritativeUpstreamSelectorForwarding =
    normalizedExplicitForwardPairs != [ ] || nodeForwardingEnabled == false || hasExplicitSelectorForwarding;
}
