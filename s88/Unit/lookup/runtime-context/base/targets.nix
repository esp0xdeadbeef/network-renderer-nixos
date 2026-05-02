{ lib, common }:

let
  inherit (common) sortedAttrNames controlPlaneData siteTreeFromRoot;

  siteEntries =
    cpm:
    let
      cpmData = controlPlaneData cpm;
    in
    lib.concatMap (
      rootName:
      let
        siteTree = siteTreeFromRoot cpmData.${rootName};
      in
      map (siteName: {
        inherit rootName siteName;
        site = siteTree.${siteName};
      }) (sortedAttrNames siteTree)
    ) (sortedAttrNames cpmData);

  runtimeTargetAttrNamesForEntry =
    entry:
    if entry.site ? runtimeTargets && builtins.isAttrs entry.site.runtimeTargets then
      sortedAttrNames entry.site.runtimeTargets
    else
      [ ];

  runtimeTargetInstanceId =
    { rootName, siteName, unitName }:
    builtins.concatStringsSep "::" (
      lib.filter builtins.isString [ rootName siteName unitName ]
    );

  runtimeTargetEntries =
    cpm:
    lib.concatMap (
      entry:
      map (
        unitName:
        entry
        // {
          inherit unitName;
          runtimeTarget = entry.site.runtimeTargets.${unitName};
          instanceId = runtimeTargetInstanceId {
            inherit (entry) rootName siteName;
            inherit unitName;
          };
        }
      ) (runtimeTargetAttrNamesForEntry entry)
    ) (siteEntries cpm);

  runtimeTargetEntriesById =
    cpm:
    builtins.listToAttrs (
      map (entry: {
        name = entry.instanceId;
        value = entry;
      }) (runtimeTargetEntries cpm)
    );

  runtimeTargetEntryForUnit =
    { cpm, unitName, file ? "s88/Unit/lookup/runtime-context.nix" }:
    let
      byId = runtimeTargetEntriesById cpm;
      rawMatches = lib.filter (entry: entry.unitName == unitName) (runtimeTargetEntries cpm);
    in
    if builtins.hasAttr unitName byId then
      byId.${unitName}
    else if builtins.length rawMatches == 1 then
      builtins.head rawMatches
    else if rawMatches == [ ] then
      throw ''
        ${file}: missing runtime target for unit '${unitName}'

        known runtime target instances:
        ${builtins.concatStringsSep "\n  - " ([ "" ] ++ (sortedAttrNames byId))}
      ''
    else
      throw ''
        ${file}: multiple runtime target instances matched legacy unit name '${unitName}'

        matching runtime target instances:
        ${builtins.concatStringsSep "\n  - " ([ "" ] ++ (map (entry: entry.instanceId) rawMatches))}
      '';

  runtimeTargetIdForEntry =
    entry:
    let target = entry.runtimeTarget;
    in
    if target ? runtimeTargetId && builtins.isString target.runtimeTargetId then
      target.runtimeTargetId
    else if target ? logicalNode && builtins.isAttrs target.logicalNode && builtins.isString (target.logicalNode.name or null) then
      target.logicalNode.name
    else
      entry.unitName;
in
rec {
  inherit siteEntries runtimeTargetInstanceId runtimeTargetEntries runtimeTargetIdForEntry;

  runtimeTargets = cpm: builtins.mapAttrs (_: entry: entry.runtimeTarget) (runtimeTargetEntriesById cpm);

  siteEntryForUnit =
    { cpm, unitName, file ? "s88/Unit/lookup/runtime-context.nix" }:
    let entry = runtimeTargetEntryForUnit { inherit cpm unitName file; };
    in
    {
      inherit (entry) rootName siteName site unitName instanceId runtimeTarget;
    };

  runtimeTargetForUnit =
    { cpm, unitName, file ? "s88/Unit/lookup/runtime-context.nix" }:
    (runtimeTargetEntryForUnit { inherit cpm unitName file; }).runtimeTarget;

  logicalNodeForUnit =
    { cpm, inventory ? { }, unitName, file ? "s88/Unit/lookup/runtime-context.nix" }:
    let target = runtimeTargetForUnit { inherit cpm unitName file; };
    in if target ? logicalNode && builtins.isAttrs target.logicalNode then target.logicalNode else { };

  runtimeTargetIdForUnit =
    { cpm, inventory ? { }, unitName, file ? "s88/Unit/lookup/runtime-context.nix" }:
    runtimeTargetIdForEntry (runtimeTargetEntryForUnit { inherit cpm unitName file; });

  logicalNodeNameForUnit =
    { cpm, inventory ? { }, unitName, file ? "s88/Unit/lookup/runtime-context.nix" }:
    let
      logicalNode = logicalNodeForUnit { inherit cpm inventory unitName file; };
      runtimeTargetId = runtimeTargetIdForUnit { inherit cpm inventory unitName file; };
    in
    if logicalNode ? name && builtins.isString logicalNode.name then logicalNode.name else runtimeTargetId;

  logicalNodeIdentityForUnit =
    { cpm, inventory ? { }, unitName, file ? "s88/Unit/lookup/runtime-context.nix" }:
    let
      entry = runtimeTargetEntryForUnit { inherit cpm unitName file; };
      logicalNode = logicalNodeForUnit { inherit cpm inventory unitName file; };
      siteName = if logicalNode ? site && builtins.isString logicalNode.site then logicalNode.site else entry.siteName or null;
      identityName = if logicalNode ? name && builtins.isString logicalNode.name then logicalNode.name else runtimeTargetIdForEntry entry;
      segments = lib.filter builtins.isString [ entry.rootName siteName identityName ];
    in
    if segments != [ ] then builtins.concatStringsSep "::" segments else unitName;

  roleForUnit =
    { cpm, inventory ? { }, unitName, file ? "s88/Unit/lookup/runtime-context.nix" }:
    let
      target = runtimeTargetForUnit { inherit cpm unitName file; };
      logicalNode = logicalNodeForUnit { inherit cpm inventory unitName file; };
    in
    if target ? role && builtins.isString target.role then target.role else logicalNode.role or null;
}
