{ lib }:

let
  sortedAttrNames = attrs: lib.sort builtins.lessThan (builtins.attrNames attrs);

  cpmDataFor =
    cpm:
    if cpm ? control_plane_model
      && builtins.isAttrs cpm.control_plane_model
      && cpm.control_plane_model ? data
      && builtins.isAttrs cpm.control_plane_model.data
    then
      cpm.control_plane_model.data
    else if cpm ? data && builtins.isAttrs cpm.data then
      cpm.data
    else if builtins.isAttrs cpm then
      cpm
    else
      { };

  siteTreeForEnterprise =
    enterprise:
    if enterprise ? site && builtins.isAttrs enterprise.site then
      enterprise.site
    else if builtins.isAttrs enterprise then
      enterprise
    else
      { };

  runtimeTargetsFromSite =
    site:
    if site ? runtimeTargets && builtins.isAttrs site.runtimeTargets then
      site.runtimeTargets
    else
      { };

  realizationNodesFor =
    inventory:
    if inventory ? realization
      && builtins.isAttrs inventory.realization
      && inventory.realization ? nodes
      && builtins.isAttrs inventory.realization.nodes
    then
      inventory.realization.nodes
    else
      { };

  placementHostOfTarget =
    target:
    if target ? placement
      && builtins.isAttrs target.placement
      && target.placement ? host
      && builtins.isString target.placement.host
    then
      target.placement.host
    else
      null;

  logicalNodeNameOfTarget =
    target:
    if target ? logicalNode
      && builtins.isAttrs target.logicalNode
      && target.logicalNode ? name
      && builtins.isString target.logicalNode.name
    then
      target.logicalNode.name
    else
      null;

  roleOfTarget =
    target:
    if target ? role && builtins.isString target.role then
      target.role
    else
      null;

  realizationHostForUnit =
    {
      inventory,
      unitName,
    }:
    let
      realizationNodes = realizationNodesFor inventory;
    in
    if builtins.hasAttr unitName realizationNodes
      && builtins.isAttrs realizationNodes.${unitName}
      && realizationNodes.${unitName} ? host
      && builtins.isString realizationNodes.${unitName}.host
    then
      realizationNodes.${unitName}.host
    else
      null;

  unitBelongsToDeploymentHost =
    {
      inventory,
      deploymentHostName,
      unitName,
      target,
    }:
    let
      placementHost = placementHostOfTarget target;
      realizationHost = realizationHostForUnit {
        inherit inventory unitName;
      };
      logicalNodeName = logicalNodeNameOfTarget target;
    in
    placementHost == deploymentHostName
    || realizationHost == deploymentHostName
    || unitName == deploymentHostName
    || logicalNodeName == deploymentHostName;

  attachmentsForSite =
    site:
    if site ? attachments && builtins.isList site.attachments then
      lib.filter builtins.isAttrs site.attachments
    else if site ? attachment && builtins.isList site.attachment then
      lib.filter builtins.isAttrs site.attachment
    else
      [ ];

  tenantNameFromSegment =
    segment:
    if !(builtins.isString segment) then
      null
    else if lib.hasPrefix "tenants:" segment then
      builtins.substring 8 (builtins.stringLength segment - 8) segment
    else if lib.hasPrefix "tenant:" segment then
      builtins.substring 7 (builtins.stringLength segment - 7) segment
    else
      null;

  tenantNameForAttachment =
    attachment:
    if attachment ? kind
      && attachment.kind == "tenant"
      && attachment ? name
      && builtins.isString attachment.name
    then
      attachment.name
    else if attachment ? tenant && builtins.isString attachment.tenant then
      attachment.tenant
    else if attachment ? name && builtins.isString attachment.name then
      attachment.name
    else if attachment ? segment then
      tenantNameFromSegment attachment.segment
    else
      null;

  tenantDomainsForSite =
    site:
    if site ? domains
      && builtins.isAttrs site.domains
      && site.domains ? tenants
      && builtins.isList site.domains.tenants
    then
      lib.filter builtins.isAttrs site.domains.tenants
    else
      [ ];
in
rec {
  inherit
    cpmDataFor
    logicalNodeNameOfTarget
    placementHostOfTarget
    realizationHostForUnit
    realizationNodesFor
    roleOfTarget
    runtimeTargetsFromSite
    siteTreeForEnterprise
    sortedAttrNames
    tenantNameForAttachment
    unitBelongsToDeploymentHost
    ;

  siteEntries =
    cpm:
    let
      cpmData = cpmDataFor cpm;
      enterpriseNames = sortedAttrNames cpmData;
    in
    lib.concatMap
      (
        enterpriseName:
        let
          siteTree = siteTreeForEnterprise cpmData.${enterpriseName};
          siteNames = sortedAttrNames siteTree;
        in
        map
          (
            siteName:
            {
              inherit enterpriseName siteName;
              site = siteTree.${siteName};
              runtimeTargets = runtimeTargetsFromSite siteTree.${siteName};
            }
          )
          siteNames
      )
      enterpriseNames;

  runtimeTargets =
    cpm:
    lib.foldl'
      (
        acc: entry:
        acc // entry.runtimeTargets
      )
      { }
      (siteEntries cpm);

  runtimeTargetForUnit =
    {
      cpm,
      unitName,
      file ? "lib/runtime-context.nix",
    }:
    let
      targets = runtimeTargets cpm;
      targetNames = sortedAttrNames targets;
    in
    if builtins.hasAttr unitName targets then
      targets.${unitName}
    else
      throw ''
        ${file}: missing runtime target for unit '${unitName}'

        known runtime targets:
        ${builtins.concatStringsSep "\n  - " ([ "" ] ++ targetNames)}
      '';

  siteEntriesForUnit =
    {
      cpm,
      unitName,
    }:
    lib.filter
      (
        entry:
        builtins.hasAttr unitName entry.runtimeTargets
      )
      (siteEntries cpm);

  siteEntryForUnit =
    {
      cpm,
      unitName,
      file ? "lib/runtime-context.nix",
    }:
    let
      matches = siteEntriesForUnit {
        inherit cpm unitName;
      };
      renderedMatches =
        map
          (entry: "${entry.enterpriseName}.${entry.siteName}")
          matches;
    in
    if builtins.length matches == 1 then
      builtins.head matches
    else if builtins.length matches == 0 then
      throw ''
        ${file}: no site contains runtime target '${unitName}'
      ''
    else
      throw ''
        ${file}: runtime target '${unitName}' appears in multiple sites

        matches:
        ${builtins.concatStringsSep "\n  - " ([ "" ] ++ renderedMatches)}
      '';

  unitNamesForRoleOnDeploymentHost =
    {
      cpm,
      inventory,
      deploymentHostName,
      role,
      file ? "lib/runtime-context.nix",
    }:
    let
      targets = runtimeTargets cpm;
      unitNames = sortedAttrNames targets;
      selected =
        lib.filter
          (
            unitName:
            let
              target = targets.${unitName};
            in
            roleOfTarget target == role
            && unitBelongsToDeploymentHost {
              inherit inventory deploymentHostName unitName target;
            }
          )
          unitNames;
    in
    selected;

  siteEntriesForDeploymentHost =
    {
      cpm,
      inventory,
      deploymentHostName,
    }:
    let
      entries = siteEntries cpm;
    in
    lib.filter
      (
        entry:
        builtins.any
          (
            unitName:
            unitBelongsToDeploymentHost {
              inherit inventory deploymentHostName unitName;
              target = entry.runtimeTargets.${unitName};
            }
          )
          (sortedAttrNames entry.runtimeTargets)
      )
      entries;

  runtimeTargetsForDeploymentHost =
    {
      cpm,
      inventory,
      deploymentHostName,
    }:
    lib.foldl'
      (
        acc: entry:
        acc // entry.runtimeTargets
      )
      { }
      (siteEntriesForDeploymentHost {
        inherit cpm inventory deploymentHostName;
      });

  enterprisesForDeploymentHost =
    {
      cpm,
      inventory,
      deploymentHostName,
    }:
    let
      entries = siteEntriesForDeploymentHost {
        inherit cpm inventory deploymentHostName;
      };

      enterpriseNames =
        lib.unique (map (entry: entry.enterpriseName) entries);
    in
    builtins.listToAttrs (
      map
        (
          enterpriseName:
          {
            name = enterpriseName;
            value =
              builtins.listToAttrs (
                map
                  (
                    entry:
                    {
                      name = entry.siteName;
                      value = entry.site;
                    }
                  )
                  (lib.filter (entry: entry.enterpriseName == enterpriseName) entries)
              );
          }
        )
        enterpriseNames
    );

  tenantAttachmentForUnit =
    {
      cpm,
      unitName,
      file ? "lib/runtime-context.nix",
    }:
    let
      entry = siteEntryForUnit {
        inherit cpm unitName file;
      };

      matches =
        lib.filter
          (
            attachment:
            (attachment.unit or null) == unitName
            && tenantNameForAttachment attachment != null
          )
          (attachmentsForSite entry.site);

      renderedMatches =
        map
          (
            attachment:
            let
              tenantName = tenantNameForAttachment attachment;
            in
            "${unitName}:${tenantName}"
          )
          matches;
    in
    if builtins.length matches == 1 then
      {
        attachment = builtins.head matches;
        tenantName = tenantNameForAttachment (builtins.head matches);
        siteEntry = entry;
      }
    else if builtins.length matches == 0 then
      throw ''
        ${file}: no tenant attachment could be resolved for unit '${unitName}'
      ''
    else
      throw ''
        ${file}: multiple tenant attachments matched unit '${unitName}'

        matches:
        ${builtins.concatStringsSep "\n  - " ([ "" ] ++ renderedMatches)}
      '';

  tenantNameForUnit =
    {
      cpm,
      unitName,
      file ? "lib/runtime-context.nix",
    }:
    (
      tenantAttachmentForUnit {
        inherit cpm unitName file;
      }
    ).tenantName;

  tenantDomainForUnit =
    {
      cpm,
      unitName,
      file ? "lib/runtime-context.nix",
    }:
    let
      entry = siteEntryForUnit {
        inherit cpm unitName file;
      };

      tenantName = tenantNameForUnit {
        inherit cpm unitName file;
      };

      matches =
        lib.filter
          (
            tenantDomain:
            (tenantDomain.name or null) == tenantName
          )
          (tenantDomainsForSite entry.site);
    in
    if builtins.length matches == 1 then
      builtins.head matches
    else if builtins.length matches == 0 then
      throw ''
        ${file}: no tenant domain matched unit '${unitName}' for tenant '${tenantName}'
      ''
    else
      throw ''
        ${file}: multiple tenant domains matched unit '${unitName}' for tenant '${tenantName}'
      '';
}
