{ lib
, renderer
, repoRoot
, cpm ? null
, cpmPath ? null
, inventory ? { }
, exampleDir ? null
,
}:

# NOTE: inventoryPath parameter removed (CMC-NIXOS-REMOVE-INTENT-INVENTORY).
# Per FS-310-HDS-010-SDS-010-SMS-100, renderers must consume ONLY CPM output.
# Loading inventory.nix from disk is a violation. Inventory must come from
# the 'inventory' parameter or be extracted from CPM output.

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
    else if
      builtins.isAttrs cpmValue
      && cpmValue ? control_plane_model
      && builtins.isAttrs cpmValue.control_plane_model
      && cpmValue.control_plane_model ? inventory
      && builtins.isAttrs cpmValue.control_plane_model.inventory
    then
      cpmValue.control_plane_model.inventory
    else
      { };

  # Resolved inventory: use provided inventory, otherwise extract from CPM.
  # No disk-based fallback to inventory.nix — SMS-100 violation removed.
  resolvedInventory =
    if inventory != { } then
      inventory
    else
      inventoryFromCpm controlPlane;
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
    # CMC-NIXOS-REMOVE-INTENT-V2: inventoryPath removed — renderers must not
    # carry upstream file paths (FS-310-HDS-010-SDS-010-SMS-100).
    exampleDir = resolvedExampleDir;
  };
}
