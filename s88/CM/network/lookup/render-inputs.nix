{
  lib,
  renderer,
  repoRoot,
  cpm ? null,
  cpmPath ? null,
  inventory ? { },
  inventoryPath ? null,
  exampleDir ? null,
}:

let
  firstExistingPath =
    candidates:
    let
      existing = lib.filter (path: path != null && builtins.pathExists (builtins.toPath path)) candidates;
    in
    if existing == [ ] then null else builtins.head existing;

  resolvedCpmPath = if cpmPath == null then null else builtins.toString cpmPath;
  requestedInventoryPath = if inventoryPath == null then null else builtins.toString inventoryPath;

  resolvedExampleDir =
    if exampleDir != null then
      builtins.toString exampleDir
    else if resolvedCpmPath != null then
      builtins.dirOf resolvedCpmPath
    else
      null;

  resolvedInventoryPath =
    if requestedInventoryPath != null then
      requestedInventoryPath
    else
      firstExistingPath [
        (if resolvedExampleDir != null then "${resolvedExampleDir}/inventory.nix" else null)
        (if resolvedExampleDir != null then "${resolvedExampleDir}/inputs/inventory.nix" else null)
      ];

  controlPlane =
    if cpm != null then
      cpm
    else if resolvedCpmPath != null then
      renderer.loadControlPlane (builtins.toPath resolvedCpmPath)
    else
      throw ''
        s88/CM/network/lookup/render-inputs.nix: requires either cpm or cpmPath
      '';

  resolvedInventory =
    if inventory != { } then
      inventory
    else if resolvedInventoryPath != null then
      renderer.loadInventory (builtins.toPath resolvedInventoryPath)
    else
      { };
in
{
  inherit
    controlPlane
    resolvedInventory
    resolvedCpmPath
    resolvedInventoryPath
    resolvedExampleDir
    ;

  metadataSourcePaths = {
    repoRoot = builtins.toString repoRoot;
    cpmPath = resolvedCpmPath;
    inventoryPath = resolvedInventoryPath;
    exampleDir = resolvedExampleDir;
  };
}
