{ lib, base, deployment }:

{
  unitNamesForRoleOnDeploymentHost =
    { cpm, inventory ? { }, deploymentHostName, role, file ? "s88/Unit/lookup/runtime-context.nix" }:
    let targets = base.runtimeTargets cpm;
    in
    lib.filter (
      unitName:
      base.roleForUnit { inherit cpm inventory unitName file; } == role
      && deployment.deploymentHostForUnit { inherit cpm inventory unitName file; } == deploymentHostName
    ) (base.sortedAttrNames targets);

  selectedRoleNamesForUnits =
    { cpm, inventory ? { }, selectedUnits, file ? "s88/Unit/lookup/runtime-context.nix" }:
    lib.unique (
      lib.filter builtins.isString (
        map (unitName: base.roleForUnit { inherit cpm inventory unitName file; }) selectedUnits
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
