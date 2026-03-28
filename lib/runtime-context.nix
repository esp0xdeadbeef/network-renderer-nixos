{ lib }:

let
  sortedAttrNames = attrs: lib.sort builtins.lessThan (builtins.attrNames attrs);

  firstOrNull = values:
    if values == [ ] then null else builtins.head values;

  controlPlaneData = cpm:
    if cpm ? control_plane_model
      && builtins.isAttrs cpm.control_plane_model
      && cpm.control_plane_model ? data
      && builtins.isAttrs cpm.control_plane_model.data
    then
      cpm.control_plane_model.data
    else if cpm ? data && builtins.isAttrs cpm.data then
      cpm.data
    else
      { };

  siteTreeForEnterprise = enterprise:
    if enterprise ? site && builtins.isAttrs enterprise.site then
      enterprise.site
    else if builtins.isAttrs enterprise then
      enterprise
    else
      { };

  siteEntries = cpm:
    let
      cpmData = controlPlaneData cpm;
    in
    lib.concatMap
      (enterpriseName:
        let
          siteTree = siteTreeForEnterprise cpmData.${enterpriseName};
        in
        map
          (siteName: {
            inherit enterpriseName siteName;
            site = siteTree.${siteName};
          })
          (sortedAttrNames siteTree))
      (sortedAttrNames cpmData);

  runtimeTargets = cpm:
    lib.foldl'
      (acc: entry:
        acc
        // (
          if entry.site ? runtimeTargets && builtins.isAttrs entry.site.runtimeTargets then
            entry.site.runtimeTargets
          else
            { }
        ))
      { }
      (siteEntries cpm);

  siteEntryForUnit =
    {
      cpm,
      unitName,
      file ? "lib/runtime-context.nix",
    }:
    let
      matches =
        lib.filter
          (entry:
            entry.site ? runtimeTargets
            && builtins.isAttrs entry.site.runtimeTargets
            && builtins.hasAttr unitName entry.site.runtimeTargets)
          (siteEntries cpm);
    in
    if builtins.length matches == 1 then
      builtins.head matches
    else if matches == [ ] then
      throw ''
        ${file}: no site entry matched unit '${unitName}'
      ''
    else
      throw ''
        ${file}: multiple site entries matched unit '${unitName}'
      '';

  runtimeTargetForUnit =
    {
      cpm,
      unitName,
      file ? "lib/runtime-context.nix",
    }:
    let
      targets = runtimeTargets cpm;
    in
    if builtins.hasAttr unitName targets && builtins.isAttrs targets.${unitName} then
      targets.${unitName}
    else
      throw ''
        ${file}: missing runtime target for unit '${unitName}'

        known runtime targets:
        ${builtins.concatStringsSep "\n  - " ([ "" ] ++ sortedAttrNames targets)}
      '';

  logicalNodeForUnit =
    {
      cpm,
      inventory,
      unitName,
      file ? "lib/runtime-context.nix",
    }:
    let
      target = runtimeTargetForUnit {
        inherit cpm unitName file;
      };

      realizationNode =
        if inventory ? realization
          && builtins.isAttrs inventory.realization
          && inventory.realization ? nodes
          && builtins.isAttrs inventory.realization.nodes
          && builtins.hasAttr unitName inventory.realization.nodes
        then
          inventory.realization.nodes.${unitName}
        else
          null;
    in
    if target ? logicalNode && builtins.isAttrs target.logicalNode then
      target.logicalNode
    else if realizationNode != null
      && realizationNode ? logicalNode
      && builtins.isAttrs realizationNode.logicalNode
    then
      realizationNode.logicalNode
    else
      { };

  roleForUnit =
    {
      cpm,
      inventory,
      unitName,
      file ? "lib/runtime-context.nix",
    }:
    let
      target = runtimeTargetForUnit {
        inherit cpm unitName file;
      };

      logicalNode = logicalNodeForUnit {
        inherit cpm inventory unitName file;
      };
    in
    if target ? role && builtins.isString target.role then
      target.role
    else
      logicalNode.role or null;

  deploymentHostForUnit =
    {
      cpm,
      inventory,
      unitName,
      file ? "lib/runtime-context.nix",
    }:
    let
      target = runtimeTargetForUnit {
        inherit cpm unitName file;
      };

      realizationNode =
        if inventory ? realization
          && builtins.isAttrs inventory.realization
          && inventory.realization ? nodes
          && builtins.isAttrs inventory.realization.nodes
          && builtins.hasAttr unitName inventory.realization.nodes
        then
          inventory.realization.nodes.${unitName}
        else
          null;
    in
    if target ? placement
      && builtins.isAttrs target.placement
      && target.placement ? host
      && builtins.isString target.placement.host
    then
      target.placement.host
    else if realizationNode != null
      && realizationNode ? host
      && builtins.isString realizationNode.host
    then
      realizationNode.host
    else
      null;

  unitNamesForDeploymentHost =
    {
      cpm,
      inventory,
      deploymentHostName,
      file ? "lib/runtime-context.nix",
    }:
    let
      targets = runtimeTargets cpm;
    in
    lib.filter
      (unitName:
        deploymentHostForUnit {
          inherit cpm inventory unitName file;
        } == deploymentHostName)
      (sortedAttrNames targets);

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
    in
    lib.filter
      (unitName:
        roleForUnit {
          inherit cpm inventory unitName file;
        } == role
        && deploymentHostForUnit {
          inherit cpm inventory unitName file;
        } == deploymentHostName)
      (sortedAttrNames targets);

  enterpriseNamesForUnit =
    {
      cpm,
      unitName,
      file ? "lib/runtime-context.nix",
    }:
    let
      entry = siteEntryForUnit {
        inherit cpm unitName file;
      };
    in
    [ entry.enterpriseName ];

  siteNamesForUnit =
    {
      cpm,
      unitName,
      file ? "lib/runtime-context.nix",
    }:
    let
      entry = siteEntryForUnit {
        inherit cpm unitName file;
      };
    in
    [ entry.siteName ];

in
{
  inherit
    siteEntries
    runtimeTargets
    siteEntryForUnit
    runtimeTargetForUnit
    logicalNodeForUnit
    roleForUnit
    deploymentHostForUnit
    unitNamesForDeploymentHost
    unitNamesForRoleOnDeploymentHost
    enterpriseNamesForUnit
    siteNamesForUnit
    ;
}
