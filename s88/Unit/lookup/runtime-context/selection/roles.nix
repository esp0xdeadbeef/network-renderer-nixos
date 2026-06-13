{ lib, base, deployment }:

{
  unitNamesForRoleOnDeploymentHost =
    { cpm, source ? { }, deploymentHostName, role, file ? "s88/Unit/lookup/runtime-context.nix" }:
    let targets = base.runtimeTargets cpm;
    in
    lib.filter
      (
        unitName:
        base.roleForUnit { inherit cpm source unitName file; } == role
        && deployment.deploymentHostForUnit { inherit cpm source unitName file; } == deploymentHostName
      )
      (base.sortedAttrNames targets);

  selectedRoleNamesForUnits =
    { cpm, source ? { }, selectedUnits, file ? "s88/Unit/lookup/runtime-context.nix" }:
    lib.unique (
      lib.filter builtins.isString (
        map (unitName: base.roleForUnit { inherit cpm source unitName file; }) selectedUnits
      )
    );

  rootNamesForUnit =
    { cpm, unitName, file ? "s88/Unit/lookup/runtime-context.nix" }:
    let entry = base.siteEntryForUnit { inherit cpm unitName file; };
    in [ entry.rootName ];

  siteNamesForUnit =
    { cpm, unitName, file ? "s88/Unit/lookup/runtime-context.nix" }:
    let entry = base.siteEntryForUnit { inherit cpm unitName file; };
    in [ entry.siteName ];
}
