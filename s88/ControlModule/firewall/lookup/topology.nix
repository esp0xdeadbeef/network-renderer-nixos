{
  lib,
  cpm,
  runtimeTarget,
  unitKey ? null,
  unitName ? null,
  roleName ? null,
}:

let
  sortedAttrNames = attrs: lib.sort builtins.lessThan (builtins.attrNames attrs);

  controlPlaneData =
    if
      cpm ? control_plane_model
      && builtins.isAttrs cpm.control_plane_model
      && cpm.control_plane_model ? data
      && builtins.isAttrs cpm.control_plane_model.data
    then
      cpm.control_plane_model.data
    else if cpm ? data && builtins.isAttrs cpm.data then
      cpm.data
    else
      { };

  siteTreeFromRoot =
    rootValue:
    if rootValue ? site && builtins.isAttrs rootValue.site then
      rootValue.site
    else if builtins.isAttrs rootValue then
      rootValue
    else
      { };

  logicalNodeOf =
    target:
    if target ? logicalNode && builtins.isAttrs target.logicalNode then target.logicalNode else { };

  placementRuntimeTargetIdOf =
    target:
    if
      target ? placement
      && builtins.isAttrs target.placement
      && target.placement ? runtimeTargetId
      && builtins.isString target.placement.runtimeTargetId
    then
      target.placement.runtimeTargetId
    else
      null;

  runtimeTargetIdOf =
    target:
    if target ? runtimeTargetId && builtins.isString target.runtimeTargetId then
      target.runtimeTargetId
    else
      placementRuntimeTargetIdOf target;

  logicalNameOf =
    target:
    let
      logicalNode = logicalNodeOf target;
    in
    if logicalNode ? name && builtins.isString logicalNode.name then logicalNode.name else null;

  roleOf =
    target:
    let
      logicalNode = logicalNodeOf target;
    in
    if target ? role && builtins.isString target.role then
      target.role
    else if logicalNode ? role && builtins.isString logicalNode.role then
      logicalNode.role
    else
      null;

  rootHintOf =
    target:
    let
      logicalNode = logicalNodeOf target;
    in
    if logicalNode ? enterprise && builtins.isString logicalNode.enterprise then
      logicalNode.enterprise
    else
      null;

  siteHintOf =
    target:
    let
      logicalNode = logicalNodeOf target;
    in
    if logicalNode ? site && builtins.isString logicalNode.site then logicalNode.site else null;

  runtimeTargetInstanceId =
    {
      rootName,
      siteName,
      rawUnitKey,
    }:
    builtins.concatStringsSep "::" (
      lib.filter builtins.isString [
        rootName
        siteName
        rawUnitKey
      ]
    );

  siteEntries = lib.concatMap (
    rootName:
    let
      siteTree = siteTreeFromRoot controlPlaneData.${rootName};
    in
    map (siteName: {
      inherit rootName siteName;
      site = siteTree.${siteName};
    }) (sortedAttrNames siteTree)
  ) (sortedAttrNames controlPlaneData);

  runtimeTargetEntries = lib.concatMap (
    siteEntry:
    let
      siteRuntimeTargets =
        if siteEntry.site ? runtimeTargets && builtins.isAttrs siteEntry.site.runtimeTargets then
          siteEntry.site.runtimeTargets
        else
          { };
    in
    map (
      rawUnitKey:
      let
        target = siteRuntimeTargets.${rawUnitKey};
      in
      {
        inherit (siteEntry) rootName siteName site;
        inherit rawUnitKey;
        unitKey = runtimeTargetInstanceId {
          inherit (siteEntry) rootName siteName;
          inherit rawUnitKey;
        };
        runtimeTarget = target;
        role = roleOf target;
      }
    ) (sortedAttrNames siteRuntimeTargets)
  ) siteEntries;

  aliasesForTarget =
    runtimeUnitKey: target:
    lib.unique (
      lib.filter builtins.isString [
        runtimeUnitKey
        (runtimeTargetIdOf target)
        (placementRuntimeTargetIdOf target)
        (logicalNameOf target)
      ]
    );

  aliasesForEntry =
    entry:
    lib.unique (
      [
        entry.unitKey
      ]
      ++ (aliasesForTarget entry.rawUnitKey entry.runtimeTarget)
    );

  runtimeTargetEntriesByAlias = builtins.foldl' (
    acc: entry:
    builtins.foldl' (
      aliasAcc: alias:
      aliasAcc
      // {
        ${alias} = (aliasAcc.${alias} or [ ]) ++ [ entry ];
      }
    ) acc (aliasesForEntry entry)
  ) { } runtimeTargetEntries;

  uniqueEntries =
    entries:
    let
      names = lib.unique (map (entry: entry.unitKey) entries);
    in
    map (name: builtins.head (lib.filter (entry: entry.unitKey == name) entries)) names;

  currentAliases = lib.unique (
    lib.filter builtins.isString (
      [
        unitKey
        unitName
      ]
      ++ (aliasesForTarget (if unitKey != null then unitKey else unitName) runtimeTarget)
    )
  );

  currentRootHint = rootHintOf runtimeTarget;
  currentSiteHint = siteHintOf runtimeTarget;
  currentRoleHint = if roleName != null then roleName else roleOf runtimeTarget;
  currentRuntimeTargetIdHint = runtimeTargetIdOf runtimeTarget;
  currentLogicalNameHint = logicalNameOf runtimeTarget;

  entryMatchesHints =
    entry:
    let
      target = entry.runtimeTarget;
      targetLogicalName = logicalNameOf target;
      targetRuntimeTargetId = runtimeTargetIdOf target;
      targetPlacementRuntimeTargetId = placementRuntimeTargetIdOf target;
      targetRole = roleOf target;
      targetSiteHint = siteHintOf target;
    in
    (currentRootHint == null || entry.rootName == currentRootHint)
    && (
      currentSiteHint == null || entry.siteName == currentSiteHint || targetSiteHint == currentSiteHint
    )
    && (currentRoleHint == null || targetRole == currentRoleHint)
    && (
      currentLogicalNameHint == null
      || targetLogicalName == currentLogicalNameHint
      || entry.rawUnitKey == currentLogicalNameHint
      || entry.unitKey == currentLogicalNameHint
    )
    && (
      currentRuntimeTargetIdHint == null
      || targetRuntimeTargetId == currentRuntimeTargetIdHint
      || targetPlacementRuntimeTargetId == currentRuntimeTargetIdHint
    );

  aliasMatches = uniqueEntries (
    lib.concatMap (
      alias:
      if builtins.hasAttr alias runtimeTargetEntriesByAlias then
        runtimeTargetEntriesByAlias.${alias}
      else
        [ ]
    ) currentAliases
  );

  hintedAliasMatches = lib.filter entryMatchesHints aliasMatches;
  fallbackMatches = lib.filter entryMatchesHints runtimeTargetEntries;

  resolvedCurrentMatches =
    if hintedAliasMatches != [ ] then
      hintedAliasMatches
    else if aliasMatches != [ ] then
      aliasMatches
    else
      fallbackMatches;

  currentEntry =
    if builtins.length resolvedCurrentMatches == 1 then
      builtins.head resolvedCurrentMatches
    else if resolvedCurrentMatches == [ ] then
      null
    else
      throw ''
        s88/ControlModule/firewall/lookup/topology.nix: current runtime target resolved ambiguously

        aliases:
        ${builtins.toJSON currentAliases}

        matches:
        ${builtins.toJSON (map (entry: entry.unitKey) resolvedCurrentMatches)}
      '';

  hintedSiteEntries = lib.filter (
    siteEntry:
    (currentRootHint == null || siteEntry.rootName == currentRootHint)
    && (currentSiteHint == null || siteEntry.siteName == currentSiteHint)
  ) siteEntries;

  currentSiteEntry =
    if currentEntry != null then
      {
        inherit (currentEntry) rootName siteName site;
      }
    else if builtins.length hintedSiteEntries == 1 then
      builtins.head hintedSiteEntries
    else
      null;

  currentRootName = if currentSiteEntry != null then currentSiteEntry.rootName else currentRootHint;

  currentSiteName = if currentSiteEntry != null then currentSiteEntry.siteName else currentSiteHint;

  currentRoot =
    if currentRootName != null && builtins.hasAttr currentRootName controlPlaneData then
      controlPlaneData.${currentRootName}
    else
      { };

  currentSite = if currentSiteEntry != null then currentSiteEntry.site else { };

  currentSiteRuntimeTargets =
    if currentSite ? runtimeTargets && builtins.isAttrs currentSite.runtimeTargets then
      currentSite.runtimeTargets
    else
      { };

  sameSiteEntries =
    if currentSiteEntry == null then
      [ ]
    else
      lib.filter (
        entry: entry.rootName == currentSiteEntry.rootName && entry.siteName == currentSiteEntry.siteName
      ) runtimeTargetEntries;

  peerEntries =
    if currentEntry == null then
      sameSiteEntries
    else
      lib.filter (entry: entry.unitKey != currentEntry.unitKey) sameSiteEntries;

  entriesToTargets =
    entries:
    builtins.listToAttrs (
      map (entry: {
        name = entry.unitKey;
        value = entry.runtimeTarget;
      }) entries
    );

  roleNamesForEntries =
    entries: lib.unique (lib.filter builtins.isString (map (entry: entry.role) entries));

  entriesByRole =
    entries:
    builtins.listToAttrs (
      map (entryRole: {
        name = entryRole;
        value = lib.filter (entry: entry.role == entryRole) entries;
      }) (roleNamesForEntries entries)
    );

  runtimeTargetsByRole =
    entries: builtins.mapAttrs (_: roleEntries: entriesToTargets roleEntries) (entriesByRole entries);

  currentUnitKey = if currentEntry != null then currentEntry.unitKey else unitKey;

  currentRawUnitKey = if currentEntry != null then currentEntry.rawUnitKey else unitKey;

  currentRoleName = if currentEntry != null then currentEntry.role else currentRoleHint;
in
{
  inherit
    controlPlaneData
    siteEntries
    runtimeTargetEntries
    runtimeTargetEntriesByAlias
    currentEntry
    currentRootName
    currentSiteName
    currentRoot
    currentSite
    currentSiteRuntimeTargets
    sameSiteEntries
    peerEntries
    currentUnitKey
    currentRawUnitKey
    currentRoleName
    ;

  current = {
    aliases = currentAliases;
    unitKey = currentUnitKey;
    rawUnitKey = currentRawUnitKey;
    unitName = unitName;
    roleName = currentRoleName;
    inherit runtimeTarget;
    entry = currentEntry;
    rootName = currentRootName;
    siteName = currentSiteName;
    root = currentRoot;
    site = currentSite;
  };

  siteRuntimeTargets = entriesToTargets sameSiteEntries;
  peers = entriesToTargets peerEntries;
  siteRoleEntries = entriesByRole sameSiteEntries;
  peerRoleEntries = entriesByRole peerEntries;
  siteRuntimeTargetsByRole = runtimeTargetsByRole sameSiteEntries;
  peerRuntimeTargetsByRole = runtimeTargetsByRole peerEntries;
  siteRoleNames = roleNamesForEntries sameSiteEntries;
  peerRoleNames = roleNamesForEntries peerEntries;
}
