{
  lib,
  interfaceView,
  common,
}:

let
  inherit (common) sortedStrings entryFieldOr lastStringSegment;

  rawInterfaceEntries =
    if interfaceView != null && builtins.isAttrs interfaceView && interfaceView ? interfaceEntries then
      lib.filter builtins.isAttrs interfaceView.interfaceEntries
    else
      [ ];

  interfaceEntries = lib.filter (
    entry: entry ? name && builtins.isString entry.name && entry.name != ""
  ) rawInterfaceEntries;

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
      sourceKind = entryFieldOr entry "sourceKind" null;
    in
    if semanticInterface ? kind && builtins.isString semanticInterface.kind then
      semanticInterface.kind
    else if builtins.isString sourceKind then
      sourceKind
    else
      null;

  interfaceRefStrings =
    entry:
    let
      backingRef = entryFieldOr entry "backingRef" { };
    in
    sortedStrings [
      (entry.name or null)
      (entry.key or null)
      (entryFieldOr entry "sourceInterface" null)
      (entryFieldOr entry "runtimeIfName" null)
      (entryFieldOr entry "renderedIfName" null)
      (entryFieldOr entry "ifName" null)
      (entryFieldOr entry "containerInterfaceName" null)
      (entryFieldOr entry "hostInterfaceName" null)
      (entryFieldOr entry "desiredInterfaceName" null)
      (entryFieldOr entry "assignedUplinkName" null)
      (entryFieldOr entry "upstream" null)
      (if builtins.isAttrs backingRef then backingRef.name or null else null)
      (
        if builtins.isAttrs backingRef && backingRef ? id && builtins.isString backingRef.id then
          lastStringSegment "::" backingRef.id
        else
          null
      )
      (if builtins.isAttrs backingRef then backingRef.kind or null else null)
    ];

  interfaceAliasMap = builtins.listToAttrs (
    lib.concatMap (
      entry:
      let
        iface =
          if builtins.isAttrs entry && entry ? iface && builtins.isAttrs entry.iface then
            entry.iface
          else
            { };
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
      map (alias: {
        name = alias;
        value = entry.name;
      }) aliases
    ) interfaceEntries
  );

  interfaceNameForLink =
    linkName:
    let
      matches = sortedStrings (
        map (entry: entry.name) (
          lib.filter (entry: builtins.elem linkName (interfaceRefStrings entry)) interfaceEntries
        )
      );
    in
    if matches == [ ] then
      null
    else if builtins.length matches == 1 then
      builtins.head matches
    else
      throw ''
        s88/ControlModule/firewall/mapping/policy-endpoints.nix: link '${linkName}' matched multiple rendered interfaces

        matches:
        ${builtins.toJSON matches}
      '';
in
{
  inherit interfaceEntries sourceKindOf interfaceNameForLink;

  resolveInterfaceAlias =
    name:
    if builtins.isString name && builtins.hasAttr name interfaceAliasMap then
      interfaceAliasMap.${name}
    else
      null;
}
