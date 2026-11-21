{
  lib,
  renderer,
  repoRoot,
  cpm ? null,
  cpmPath ? null,
  source ? { },
  exampleDir ? null,
}:

let
  resolvedCpmPath = if cpmPath == null then null else builtins.toString cpmPath;

  resolvedExampleDir =
    if exampleDir != null then
      builtins.toString exampleDir
    else if resolvedCpmPath != null then
      builtins.dirOf resolvedCpmPath
    else
      null;

  controlPlane =
    if cpm != null then
      cpm
    else if resolvedCpmPath != null then
      renderer.loadControlPlane (builtins.toPath resolvedCpmPath)
    else
      throw ''
        s88/CM/network/lookup/render-inputs.nix: requires either cpm or cpmPath
      '';

  inventoryFromCpm =
    cpmValue:
    if
      builtins.isAttrs cpmValue && cpmValue ? globalInventory && builtins.isAttrs cpmValue.globalInventory
    then
      cpmValue.globalInventory
    else if
      builtins.isAttrs cpmValue && cpmValue ? inventory && builtins.isAttrs cpmValue.inventory
    then
      cpmValue.inventory
    else

      { };

  resolvedInventory = if source != { } then source else inventoryFromCpm controlPlane;
in
{
  inherit
    controlPlane
    resolvedInventory
    resolvedCpmPath
    resolvedExampleDir
    ;

  metadataSourcePaths = {
    repoRoot = builtins.toString repoRoot;
    cpmPath = resolvedCpmPath;

    exampleDir = resolvedExampleDir;
  };
}
