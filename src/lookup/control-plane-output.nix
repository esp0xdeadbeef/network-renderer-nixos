{
  lib,
  controlPlaneLib,
  importValue,
}:
{
  intentPath,
  inventoryPath ? null,
  intent ? null,
  inventory ? null,
}:
let
  resolvedIntent = if intent != null then intent else importValue intentPath;

  resolvedInventory =
    if inventory != null then
      inventory
    else if inventoryPath == null then
      { }
    else
      importValue inventoryPath;

  buildFromValues =
    if controlPlaneLib ? build then
      controlPlaneLib.build
    else if controlPlaneLib ? compileAndBuild then
      controlPlaneLib.compileAndBuild
    else if controlPlaneLib ? getCPM then
      args: { control_plane_model = controlPlaneLib.getCPM args; }
    else if controlPlaneLib ? get_CPM then
      args: { control_plane_model = controlPlaneLib.get_CPM args; }
    else
      throw "network-renderer-nixos: network-control-plane-model.lib is missing build/compileAndBuild/getCPM/get_CPM";

  built =
    let
      result =
        if intent == null && inventory == null && controlPlaneLib ? compileAndBuildFromPaths then
          controlPlaneLib.compileAndBuildFromPaths {
            inputPath = intentPath;
            inherit inventoryPath;
          }
        else
          buildFromValues {
            input = resolvedIntent;
            inventory = resolvedInventory;
          };
    in
    if builtins.isAttrs result then result else { control_plane_model = result; };
in
built
// {
  fabricInputs = resolvedIntent;
  globalInventory = resolvedInventory;
  inventory = resolvedInventory;
}
