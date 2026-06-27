{ lib, common, entries, resolveInterfaceTokens, runtimeTarget, nodeForwarding, nodeEgress, nodeNat, wanIfs, lanIfs }:

let
  inherit (common) sortedStrings boolOrFalse stringListFromPaths;

  hasValueAtPath =
    root: path:
    common.attrPathOrNull root path != null;

  hasAnyRolePath =
    roots: paths:
    builtins.any (path: builtins.any (root: hasValueAtPath root path) roots) paths;

  localAdapterRolePaths = [
    [ "localInterfaces" ]
    [ "localAdapterInterfaces" ]
    [ "localAdapters" ]
    [ "lanInterfaces" ]
    [ "lans" ]
    [ "forwarding" "localInterfaces" ]
    [ "forwarding" "localAdapterInterfaces" ]
    [ "forwarding" "localAdapters" ]
    [ "forwarding" "lanInterfaces" ]
    [ "participation" "localAdapterInterfaces" ]
    [ "participation" "localAdapters" ]
    [ "interfaceRoles" "localAdapters" ]
    [ "interfaceRoles" "lanInterfaces" ]
  ];

  uplinkRolePaths = [
    [ "uplinkInterfaces" ]
    [ "uplinkInterfaceNames" ]
    [ "uplinks" ]
    [ "forwarding" "uplinkInterfaces" ]
    [ "forwarding" "uplinks" ]
    [ "participation" "uplinkInterfaces" ]
    [ "participation" "uplinks" ]
    [ "egress" "exitInterfaces" ]
    [ "egress" "upstreamSelectionInterfaces" ]
    [ "egress" "uplinkInterfaces" ]
    [ "interfaceRoles" "uplinks" ]
  ];

  transitRolePaths = [
    [ "transitInterfaces" ]
    [ "transits" ]
    [ "forwarding" "transitInterfaces" ]
    [ "forwarding" "transits" ]
    [ "participation" "transitInterfaces" ]
    [ "participation" "transits" ]
    [ "interfaceRoles" "transits" ]
  ];

  wanRolePaths = [
    [ "wanInterfaces" ]
    [ "wans" ]
    [ "egress" "wanInterfaces" ]
  ];

  explicitRoleFieldNames = [
    "explicitLocalAdapter"
    "explicitUplink"
    "explicitTransit"
    "explicitWan"
  ];

  explicitNames =
    roots: paths: predicate:
    sortedStrings (
      resolveInterfaceTokens (stringListFromPaths { inherit roots paths; })
      ++ map (entry: entry.name) (lib.filter predicate entries)
    );

  explicitFieldValue =
    entry: field:
    if
      entry ? explicit
      && builtins.isAttrs entry.explicit
      && builtins.hasAttr field entry.explicit
    then
      entry.explicit.${field}
    else
      null;

  entryHasExplicitRoleContract =
    entry:
    builtins.all (field: builtins.isBool (explicitFieldValue entry field)) explicitRoleFieldNames;

  missingExplicitRoleContractInterfaces = sortedStrings (
    map (entry: entry.name or null) (lib.filter (entry: !(entryHasExplicitRoleContract entry)) entries)
  );

  namedRoleListContractPresent = hasAnyRolePath [ runtimeTarget nodeForwarding nodeEgress ] (
    localAdapterRolePaths ++ uplinkRolePaths ++ transitRolePaths ++ wanRolePaths
  );

  explicitInterfaceFlagContractPresent =
    entries != [ ] && missingExplicitRoleContractInterfaces == [ ];

  explicitRoleContractPresent =
    namedRoleListContractPresent || explicitInterfaceFlagContractPresent;

  explicitLocalAdapterNames = explicitNames [ runtimeTarget nodeForwarding ] localAdapterRolePaths
    (entry: boolOrFalse entry.explicit.explicitLocalAdapter);

  explicitUplinkNames = explicitNames [ runtimeTarget nodeForwarding nodeEgress ] uplinkRolePaths
    (entry: boolOrFalse entry.explicit.explicitUplink || boolOrFalse entry.explicit.explicitExitEligible);

  explicitTransitNames = explicitNames [ runtimeTarget nodeForwarding ] transitRolePaths
    (entry: boolOrFalse entry.explicit.explicitTransit);

  explicitWanNames = explicitNames [ runtimeTarget nodeForwarding nodeEgress ] wanRolePaths
    (entry: boolOrFalse entry.explicit.explicitWan);

  explicitExitEligibleNames = explicitNames [ runtimeTarget nodeForwarding nodeEgress ] [
    [ "uplinkInterfaces" ]
    [ "uplinkInterfaceNames" ]
    [ "exitInterfaces" ]
    [ "upstreamSelectionInterfaces" ]
    [ "egress" "exitInterfaces" ]
    [ "egress" "upstreamSelectionInterfaces" ]
  ]
    (entry: boolOrFalse entry.explicit.explicitExitEligible);

  explicitNatInterfaces = explicitNames [ runtimeTarget nodeForwarding nodeEgress nodeNat ] [
    [ "natInterfaces" ]
    [ "masqueradeInterfaces" ]
    [ "nat" "interfaces" ]
    [ "masquerade" "interfaces" ]
    [ "egress" "natInterfaces" ]
    [ "egress" "nat" "interfaces" ]
    [ "egress" "masqueradeInterfaces" ]
    [ "egress" "masquerade" "interfaces" ]
  ]
    (entry: boolOrFalse entry.explicit.explicitNatEnabled);

  explicitNat4Interfaces = explicitNames [ runtimeTarget nodeForwarding nodeEgress nodeNat ] [
    [ "natInterfaces4" ]
    [ "masqueradeInterfaces4" ]
    [ "nat" "interfaces4" ]
    [ "masquerade" "interfaces4" ]
    [ "egress" "natInterfaces4" ]
    [ "egress" "nat" "interfaces4" ]
    [ "egress" "masqueradeInterfaces4" ]
    [ "egress" "masquerade" "interfaces4" ]
  ]
    (entry: boolOrFalse entry.explicit.explicitNatEnabled);

  explicitNat6Interfaces = explicitNames [ runtimeTarget nodeForwarding nodeEgress nodeNat ] [
    [ "natInterfaces6" ]
    [ "masqueradeInterfaces6" ]
    [ "nat" "interfaces6" ]
    [ "masquerade" "interfaces6" ]
    [ "egress" "natInterfaces6" ]
    [ "egress" "nat" "interfaces6" ]
    [ "egress" "masqueradeInterfaces6" ]
    [ "egress" "masquerade" "interfaces6" ]
  ]
    (entry: boolOrFalse entry.explicit.explicitNatEnabled);

  explicitNat6SourcePrefixes = stringListFromPaths {
    roots = [ runtimeTarget nodeForwarding nodeEgress nodeNat ];
    paths = [
      [ "natSourcePrefixes6" ]
      [ "masqueradeSourcePrefixes6" ]
      [ "nat" "sourcePrefixes6" ]
      [ "masquerade" "sourcePrefixes6" ]
      [ "egress" "natSourcePrefixes6" ]
      [ "egress" "nat" "sourcePrefixes6" ]
      [ "egress" "masqueradeSourcePrefixes6" ]
      [ "egress" "masquerade" "sourcePrefixes6" ]
    ];
  };

  explicitNat4SourcePrefixes = stringListFromPaths {
    roots = [ runtimeTarget nodeForwarding nodeEgress nodeNat ];
    paths = [
      [ "natSourcePrefixes4" ]
      [ "masqueradeSourcePrefixes4" ]
      [ "nat" "sourcePrefixes4" ]
      [ "masquerade" "sourcePrefixes4" ]
      [ "egress" "natSourcePrefixes4" ]
      [ "egress" "nat" "sourcePrefixes4" ]
      [ "egress" "masqueradeSourcePrefixes4" ]
      [ "egress" "masquerade" "sourcePrefixes4" ]
    ];
  };

  explicitClampMssInterfaces = explicitNames [ runtimeTarget nodeForwarding nodeEgress nodeNat ] [
    [ "clampMssInterfaces" ]
    [ "tcpMssClampInterfaces" ]
    [ "clampMss" "interfaces" ]
    [ "tcpMssClamp" "interfaces" ]
    [ "egress" "clampMssInterfaces" ]
    [ "egress" "tcpMssClampInterfaces" ]
    [ "egress" "clampMss" "interfaces" ]
    [ "egress" "tcpMssClamp" "interfaces" ]
  ]
    (entry: boolOrFalse entry.explicit.explicitClampMss);

  overlayInterfaceNames = sortedStrings (
    map (entry: entry.name) (
      lib.filter
        (
          entry:
          (entry.sourceKind or null) == "overlay"
          || (entry ? backingRef && builtins.isAttrs entry.backingRef && (entry.backingRef.kind or null) == "overlay")
        )
        entries
    )
  );

  isOverlayEntry =
    entry:
    (entry.sourceKind or null) == "overlay"
    || (entry ? backingRef && builtins.isAttrs entry.backingRef && (entry.backingRef.kind or null) == "overlay");

  # CPM commit 3bac142 now includes p2p fabric subnets in
  # masqueradeSourcePrefixes; the renderer-side fallback that
  # derived NAT prefixes from interface addresses is removed.
  # Trace: FS-380-HDS-010-SDS-010-SMS-100.
in
{
  inherit
    explicitLocalAdapterNames explicitUplinkNames explicitTransitNames explicitWanNames
    explicitExitEligibleNames explicitNatInterfaces explicitNat4Interfaces explicitNat6Interfaces
    explicitNat4SourcePrefixes explicitNat6SourcePrefixes explicitClampMssInterfaces overlayInterfaceNames
    explicitRoleContractPresent missingExplicitRoleContractInterfaces
    ;
  resolvedLocalAdapterNames = explicitLocalAdapterNames;
  resolvedWanNames = explicitWanNames;
  resolvedLanNames = explicitLocalAdapterNames;
  resolvedTransitNames = explicitTransitNames;
  resolvedUplinkNames = explicitUplinkNames;
  resolvedAccessUplinkNames = explicitUplinkNames;
}
