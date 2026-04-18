{ lib }:

let
  sortedAttrNames = attrs: lib.sort builtins.lessThan (builtins.attrNames attrs);

  controlPlaneData =
    cpm:
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
    {
      rootName,
      siteName,
      unitName,
    }:
    builtins.concatStringsSep "::" (
      lib.filter builtins.isString [
        rootName
        siteName
        unitName
      ]
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

  runtimeTargetEntriesForRawUnitName =
    {
      cpm,
      unitName,
    }:
    lib.filter (entry: entry.unitName == unitName) (runtimeTargetEntries cpm);

  runtimeTargetEntryForUnit =
    {
      cpm,
      unitName,
      file ? "s88/Unit/lookup/runtime-context.nix",
    }:
    let
      byId = runtimeTargetEntriesById cpm;
      rawMatches = runtimeTargetEntriesForRawUnitName {
        inherit cpm unitName;
      };
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
    let
      target = entry.runtimeTarget;
    in
    if target ? runtimeTargetId && builtins.isString target.runtimeTargetId then
      target.runtimeTargetId
    else if
      target ? logicalNode
      && builtins.isAttrs target.logicalNode
      && target.logicalNode ? name
      && builtins.isString target.logicalNode.name
    then
      target.logicalNode.name
    else
      entry.unitName;

  runtimeTargets =
    cpm: builtins.mapAttrs (_: entry: entry.runtimeTarget) (runtimeTargetEntriesById cpm);

  siteEntryForUnit =
    {
      cpm,
      unitName,
      file ? "s88/Unit/lookup/runtime-context.nix",
    }:
    let
      entry = runtimeTargetEntryForUnit {
        inherit cpm unitName file;
      };
    in
    {
      inherit (entry)
        rootName
        siteName
        site
        unitName
        instanceId
        runtimeTarget
        ;
    };

  runtimeTargetForUnit =
    {
      cpm,
      unitName,
      file ? "s88/Unit/lookup/runtime-context.nix",
    }:
    (runtimeTargetEntryForUnit {
      inherit cpm unitName file;
    }).runtimeTarget;

  logicalNodeForUnit =
    {
      cpm,
      inventory ? { },
      unitName,
      file ? "s88/Unit/lookup/runtime-context.nix",
    }:
    let
      target = runtimeTargetForUnit {
        inherit cpm unitName file;
      };
    in
    if target ? logicalNode && builtins.isAttrs target.logicalNode then target.logicalNode else { };

  runtimeTargetIdForUnit =
    {
      cpm,
      inventory ? { },
      unitName,
      file ? "s88/Unit/lookup/runtime-context.nix",
    }:
    let
      entry = runtimeTargetEntryForUnit {
        inherit cpm unitName file;
      };
    in
    runtimeTargetIdForEntry entry;

  logicalNodeNameForUnit =
    {
      cpm,
      inventory ? { },
      unitName,
      file ? "s88/Unit/lookup/runtime-context.nix",
    }:
    let
      logicalNode = logicalNodeForUnit {
        inherit
          cpm
          inventory
          unitName
          file
          ;
      };

      runtimeTargetId = runtimeTargetIdForUnit {
        inherit
          cpm
          inventory
          unitName
          file
          ;
      };
    in
    if logicalNode ? name && builtins.isString logicalNode.name then
      logicalNode.name
    else
      runtimeTargetId;

  logicalNodeIdentityForUnit =
    {
      cpm,
      inventory ? { },
      unitName,
      file ? "s88/Unit/lookup/runtime-context.nix",
    }:
    let
      entry = runtimeTargetEntryForUnit {
        inherit cpm unitName file;
      };

      logicalNode = logicalNodeForUnit {
        inherit
          cpm
          inventory
          unitName
          file
          ;
      };

      siteName =
        if logicalNode ? site && builtins.isString logicalNode.site then
          logicalNode.site
        else
          entry.siteName or null;

      identityName =
        if logicalNode ? name && builtins.isString logicalNode.name then
          logicalNode.name
        else
          runtimeTargetIdForEntry entry;

      segments = lib.filter builtins.isString [
        entry.rootName
        siteName
        identityName
      ];
    in
    if segments != [ ] then builtins.concatStringsSep "::" segments else unitName;

  roleForUnit =
    {
      cpm,
      inventory ? { },
      unitName,
      file ? "s88/Unit/lookup/runtime-context.nix",
    }:
    let
      target = runtimeTargetForUnit {
        inherit cpm unitName file;
      };

      logicalNode = logicalNodeForUnit {
        inherit
          cpm
          inventory
          unitName
          file
          ;
      };
    in
    if target ? role && builtins.isString target.role then target.role else logicalNode.role or null;

  realizationNodesFor =
    {
      cpm ? null,
      inventory ? { },
    }:
    if
      inventory ? realization
      && builtins.isAttrs inventory.realization
      && inventory.realization ? nodes
      && builtins.isAttrs inventory.realization.nodes
    then
      inventory.realization.nodes
    else if
      cpm != null
      && builtins.isAttrs cpm
      && cpm ? control_plane_model
      && builtins.isAttrs cpm.control_plane_model
      && cpm.control_plane_model ? realization
      && builtins.isAttrs cpm.control_plane_model.realization
      && cpm.control_plane_model.realization ? nodes
      && builtins.isAttrs cpm.control_plane_model.realization.nodes
    then
      cpm.control_plane_model.realization.nodes
    else if
      cpm != null
      && builtins.isAttrs cpm
      && cpm ? realization
      && builtins.isAttrs cpm.realization
      && cpm.realization ? nodes
      && builtins.isAttrs cpm.realization.nodes
    then
      cpm.realization.nodes
    else
      { };

  logicalNodeForRealizationNode =
    node: if node ? logicalNode && builtins.isAttrs node.logicalNode then node.logicalNode else { };

  candidateRealizationNodeNamesForUnit =
    {
      cpm ? null,
      inventory ? { },
      unitName,
      file ? "s88/Unit/lookup/runtime-context.nix",
    }:
    let
      realizationNodes = realizationNodesFor {
        inherit cpm inventory;
      };

      runtimeTargetId =
        if cpm != null then
          runtimeTargetIdForUnit {
            inherit
              cpm
              inventory
              unitName
              file
              ;
          }
        else
          null;

      logicalNode =
        if cpm != null then
          logicalNodeForUnit {
            inherit
              cpm
              inventory
              unitName
              file
              ;
          }
        else
          { };

      logicalName =
        if logicalNode ? name && builtins.isString logicalNode.name then logicalNode.name else null;

      logicalSite =
        if logicalNode ? site && builtins.isString logicalNode.site then logicalNode.site else null;

      logicalEnterprise =
        if logicalNode ? enterprise && builtins.isString logicalNode.enterprise then
          logicalNode.enterprise
        else
          null;

      exactNames = lib.unique (
        lib.filter (name: builtins.isString name && builtins.hasAttr name realizationNodes) [
          unitName
          runtimeTargetId
          logicalName
        ]
      );

      logicalMatches = lib.filter (
        nodeName:
        let
          nodeLogical = logicalNodeForRealizationNode realizationNodes.${nodeName};
          nodeLogicalName = nodeLogical.name or null;
          nodeLogicalSite = nodeLogical.site or null;
          nodeLogicalEnterprise = nodeLogical.enterprise or null;
        in
        logicalName != null
        && nodeLogicalName == logicalName
        && (logicalSite == null || nodeLogicalSite == logicalSite)
        && (logicalEnterprise == null || nodeLogicalEnterprise == logicalEnterprise)
      ) (sortedAttrNames realizationNodes);

      runtimeTargetPrefixMatches = lib.filter (
        nodeName:
        let
          nodeLogical = logicalNodeForRealizationNode realizationNodes.${nodeName};
          nodeLogicalSite = nodeLogical.site or null;
          nodeLogicalEnterprise = nodeLogical.enterprise or null;
        in
        runtimeTargetId != null
        && lib.hasSuffix runtimeTargetId nodeName
        && (logicalSite == null || nodeLogicalSite == logicalSite)
        && (logicalEnterprise == null || nodeLogicalEnterprise == logicalEnterprise)
      ) (sortedAttrNames realizationNodes);
    in
    lib.unique (exactNames ++ logicalMatches ++ runtimeTargetPrefixMatches);

  realizationNodeForUnit =
    {
      cpm ? null,
      inventory ? { },
      unitName,
      file ? "s88/Unit/lookup/runtime-context.nix",
    }:
    let
      realizationNodes = realizationNodesFor {
        inherit cpm inventory;
      };

      candidates = candidateRealizationNodeNamesForUnit {
        inherit
          cpm
          inventory
          unitName
          file
          ;
      };
    in
    if builtins.hasAttr unitName realizationNodes && builtins.isAttrs realizationNodes.${unitName} then
      realizationNodes.${unitName}
    else if builtins.length candidates == 1 then
      realizationNodes.${builtins.head candidates}
    else if candidates == [ ] then
      null
    else
      throw ''
        ${file}: multiple realization nodes matched runtime unit '${unitName}'

        matching realization nodes:
        ${builtins.concatStringsSep "\n  - " ([ "" ] ++ candidates)}
      '';

  realizationHostForUnit =
    {
      cpm ? null,
      inventory ? { },
      unitName,
      file ? "s88/Unit/lookup/runtime-context.nix",
    }:
    let
      node = realizationNodeForUnit {
        inherit
          cpm
          inventory
          unitName
          file
          ;
      };
    in
    if node != null && node ? host && builtins.isString node.host then node.host else null;
in
{
  inherit
    sortedAttrNames
    siteEntries
    runtimeTargetInstanceId
    runtimeTargetEntries
    runtimeTargets
    siteEntryForUnit
    runtimeTargetForUnit
    runtimeTargetIdForUnit
    logicalNodeForUnit
    logicalNodeNameForUnit
    logicalNodeIdentityForUnit
    roleForUnit
    realizationNodesFor
    logicalNodeForRealizationNode
    candidateRealizationNodeNamesForUnit
    realizationNodeForUnit
    realizationHostForUnit
    ;
}
