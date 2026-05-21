{ lib, common, entries, resolveInterfaceTokens, runtimeTarget, nodeForwarding, nodeEgress, nodeNat, wanIfs, lanIfs }:

let
  inherit (common) sortedStrings boolOrFalse stringListFromPaths;

  explicitNames =
    roots: paths: predicate:
    sortedStrings (
      resolveInterfaceTokens (stringListFromPaths { inherit roots paths; })
      ++ map (entry: entry.name) (lib.filter predicate entries)
    );

  explicitLocalAdapterNames = explicitNames [ runtimeTarget nodeForwarding ] [
    [ "localInterfaces" ]
    [ "localAdapterInterfaces" ]
    [ "localAdapters" ]
    [ "forwarding" "localAdapterInterfaces" ]
    [ "forwarding" "localAdapters" ]
    [ "participation" "localAdapterInterfaces" ]
    [ "participation" "localAdapters" ]
    [ "interfaceRoles" "localAdapters" ]
  ]
    (entry: boolOrFalse entry.explicit.explicitLocalAdapter);

  explicitUplinkNames = explicitNames [ runtimeTarget nodeForwarding nodeEgress ] [
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
  ]
    (entry: boolOrFalse entry.explicit.explicitUplink || boolOrFalse entry.explicit.explicitExitEligible);

  explicitTransitNames = explicitNames [ runtimeTarget nodeForwarding ] [
    [ "transitInterfaces" ]
    [ "transits" ]
    [ "forwarding" "transitInterfaces" ]
    [ "forwarding" "transits" ]
    [ "participation" "transitInterfaces" ]
    [ "participation" "transits" ]
    [ "interfaceRoles" "transits" ]
  ]
    (entry: boolOrFalse entry.explicit.explicitTransit);

  explicitWanNames = explicitNames [ runtimeTarget nodeForwarding nodeEgress ] [
    [ "wanInterfaces" ]
    [ "wans" ]
    [ "egress" "wanInterfaces" ]
  ]
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

  fallbackWanNames = sortedStrings (wanIfs ++ map (entry: entry.name) (lib.filter (entry: entry.sourceKind == "wan") entries));
  fallbackP2pNames = sortedStrings (map (entry: entry.name) (lib.filter (entry: entry.sourceKind == "p2p") entries));
  fallbackLocalAdapterNames = sortedStrings (lanIfs ++ map (entry: entry.name) (lib.filter (entry: entry.sourceKind != "wan" && entry.sourceKind != "p2p") entries));
  fallbackLanNames = sortedStrings (lanIfs ++ map (entry: entry.name) (lib.filter (entry: !(builtins.elem entry.name fallbackWanNames)) entries));

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
in
{
  inherit
    explicitLocalAdapterNames explicitUplinkNames explicitTransitNames explicitWanNames
    explicitExitEligibleNames explicitNatInterfaces explicitNat4Interfaces explicitNat6Interfaces
    explicitNat6SourcePrefixes explicitClampMssInterfaces overlayInterfaceNames
    ;
  resolvedLocalAdapterNames = if explicitLocalAdapterNames != [ ] then explicitLocalAdapterNames else fallbackLocalAdapterNames;
  resolvedWanNames = if explicitWanNames != [ ] then explicitWanNames else fallbackWanNames;
  resolvedLanNames = if explicitLocalAdapterNames != [ ] then explicitLocalAdapterNames else fallbackLanNames;
  resolvedTransitNames = if explicitTransitNames != [ ] then explicitTransitNames else fallbackP2pNames;
  resolvedUplinkNames = if explicitUplinkNames != [ ] then explicitUplinkNames else fallbackWanNames;
  resolvedAccessUplinkNames = if explicitUplinkNames != [ ] then explicitUplinkNames else if fallbackP2pNames != [ ] then fallbackP2pNames else fallbackWanNames;
}
