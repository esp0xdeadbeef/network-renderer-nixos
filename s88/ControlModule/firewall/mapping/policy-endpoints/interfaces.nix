{ lib
, interfaceView
, common
,
}:

let
  inherit (common) sortedStrings entryFieldOr lastStringSegment;

  attrsOrEmpty = value: if builtins.isAttrs value then value else { };

  ifaceOf =
    entry:
    if builtins.isAttrs (entry.iface or null) then
      entry.iface
    else
      { };

  entryOrIfaceField =
    entry: field: default:
    let
      direct = entryFieldOr entry field null;
      iface = ifaceOf entry;
    in
    if direct != null then direct else entryFieldOr iface field default;

  rawInterfaceEntries =
    if interfaceView != null && builtins.isAttrs interfaceView && interfaceView ? interfaceEntries then
      lib.filter builtins.isAttrs interfaceView.interfaceEntries
    else
      [ ];

  interfaceEntries = lib.filter
    (
      entry: entry ? name && builtins.isString entry.name && entry.name != ""
    )
    rawInterfaceEntries;

  semanticInterfaceOf =
    entry:
    let
      semanticInterface = entryFieldOr entry "semanticInterface" null;
      semantic = entryFieldOr entry "semantic" null;
    in
    if builtins.isAttrs semanticInterface then
      semanticInterface
    else if builtins.isAttrs semantic then
      semantic
    else
      { };

  sourceKindOf =
    entry:
    let
      semanticInterface = semanticInterfaceOf entry;
      sourceKind = entryOrIfaceField entry "sourceKind" null;
    in
    if semanticInterface ? kind && builtins.isString semanticInterface.kind then
      semanticInterface.kind
    else if builtins.isString sourceKind then
      sourceKind
    else
      "";

  interfaceRefStrings =
    entry:
    let
      backingRef = entryOrIfaceField entry "backingRef" { };
      iface = ifaceOf entry;
    in
    sortedStrings [
      (entry.name or null)
      (entry.key or null)
      (entryOrIfaceField entry "sourceInterface" null)
      (entryOrIfaceField entry "runtimeIfName" null)
      (entryOrIfaceField entry "renderedIfName" null)
      (entryOrIfaceField entry "ifName" null)
      (entryOrIfaceField entry "containerInterfaceName" null)
      (entryOrIfaceField entry "hostInterfaceName" null)
      (entryOrIfaceField entry "desiredInterfaceName" null)
      (entryOrIfaceField entry "assignedUplinkName" null)
      (entryOrIfaceField entry "upstream" null)
      (iface.interfaceName or null)
      (if builtins.isAttrs backingRef then backingRef.name or null else null)
      (
        if builtins.isAttrs backingRef && backingRef ? id && builtins.isString backingRef.id then
          lastStringSegment "::" backingRef.id
        else
          null
      )
      (if builtins.isAttrs backingRef then backingRef.kind or null else null)
    ];

  interfaceLane =
    entry:
    let
      backingRef = entryOrIfaceField entry "backingRef" { };
      lane = entryOrIfaceField entry "lane" null;
      kind = sourceKindOf entry;
    in
    if lane != null && builtins.isString lane then
      lane
    else
      "";

  interfaceLaneAccessMatches =
    match:
    let
      lane = interfaceLane match;
    in
    lane != "" && lane != "uplink" && lane != "provider";

  interfaceLaneUplinkMatches =
    match:
    let
      lane = interfaceLane match;
    in
    lane == "uplink" || lane == "provider";

  interfaceAliasMap = builtins.listToAttrs (
    lib.concatMap
      (entry:
        let
          iface = ifaceOf entry;
          aliases = sortedStrings (
            lib.filter builtins.isString [
              entry.name or null
              entry.key or null
              iface.renderedIfName or null
              iface.runtimeIfName or null
              iface.sourceInterface or null
              iface.interfaceName or null
              iface.containerInterfaceName or null
              iface.hostInterfaceName or null
              iface.ifName or null
            ]
          );
        in
        map
          (alias: {
            name = alias;
            value = entry.name;
          })
          aliases
      )
      interfaceEntries
  );

  interfaceNameForLink =
    linkName:
    interfaceNameForLinkMatching linkName (_: true);

  interfaceNameForLinkMatching =
    linkName: entryMatches:
    let
      matches = sortedStrings (
        map (entry: entry.name) (
          lib.filter
            (
              entry: builtins.elem linkName (interfaceRefStrings entry) && entryMatches entry
            )
            interfaceEntries
        )
      );
    in
    if matches == [ ] then
      null
    else if builtins.length matches == 1 then
      builtins.head matches
    else
      # Prefer non-p2p session/overlay entries; fall back to first match
      let
        nonP2p = lib.filter
          (name:
            let
              candidates = lib.filter (e: e.name == name) interfaceEntries;
              entry = if candidates != [ ] then builtins.head candidates else { };
              kind = sourceKindOf entry;
            in
            kind != "" && kind != "p2p"
          )
          matches;
      in
      if nonP2p != [ ] then builtins.head nonP2p else builtins.head matches;
in
{
  inherit
    interfaceEntries
    interfaceLaneAccessMatches
    interfaceLaneUplinkMatches
    interfaceNameForLink
    interfaceNameForLinkMatching
    sourceKindOf
    ;

  resolveInterfaceAlias =
    name:
    if builtins.isString name && builtins.hasAttr name interfaceAliasMap then
      interfaceAliasMap.${name}
    else
      null;
}
