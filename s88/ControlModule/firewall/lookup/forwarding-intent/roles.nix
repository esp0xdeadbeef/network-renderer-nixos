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

  # Derive NAT source prefixes from fabric (non-WAN, non-overlay) interface addresses.
  # Core-upstream-vlan4 receives traffic from the entire fabric chain, and the CPM
  # explicit list only covers tenant IPs.  Include the /31, /30, /29 and /24 subnets
  # of every p2p/tenant interface so provider-handoff source IPs are masqueraded.
  interfaceAddr4CIDR =
    addr4:
    let
      parts = lib.splitString "/" addr4;
      prefix = builtins.elemAt parts 0;
      mask = if builtins.length parts >= 2 then builtins.elemAt parts 1 else "";
    in
    if prefix != "" && mask != "" && mask != "32" then "${prefix}/${mask}" else "";
  interfaceNat4Prefixes = lib.unique (
    builtins.filter (s: s != "") (
      map (entry: interfaceAddr4CIDR (entry.addr4 or ""))
      (lib.filter (entry:
        !(boolOrFalse entry.explicit.explicitWan) && !(entry.sourceKind or null == "pppoe-session") && !(isOverlayEntry entry)
      ) entries)
    )
  );
  interfaceNat6Prefixes = lib.unique (
    builtins.filter (s: s != "") (
      map (entry:
        let
          addr6 = entry.addr6 or "";
          parts = lib.splitString "/" addr6;
          prefix = builtins.elemAt parts 0;
          mask = if builtins.length parts >= 2 then builtins.elemAt parts 1 else "";
        in
        if prefix != "" && mask != "" && mask != "128" then "${prefix}/${mask}" else ""
      )
      (lib.filter (entry:
        !(boolOrFalse entry.explicit.explicitWan) && !(entry.sourceKind or null == "pppoe-session") && !(isOverlayEntry entry)
      ) entries)
    )
  );
in
{
  inherit
    explicitLocalAdapterNames explicitUplinkNames explicitTransitNames explicitWanNames
    explicitExitEligibleNames explicitNatInterfaces explicitNat4Interfaces explicitNat6Interfaces
    explicitNat4SourcePrefixes explicitNat6SourcePrefixes explicitClampMssInterfaces overlayInterfaceNames
    interfaceNat4Prefixes interfaceNat6Prefixes
    ;
  resolvedLocalAdapterNames = explicitLocalAdapterNames;
  resolvedWanNames = explicitWanNames;
  resolvedLanNames = explicitLocalAdapterNames;
  resolvedTransitNames = explicitTransitNames;
  resolvedUplinkNames = explicitUplinkNames;
  resolvedAccessUplinkNames = explicitUplinkNames;
}
