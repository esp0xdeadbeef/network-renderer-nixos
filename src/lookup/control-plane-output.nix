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

  builder =
    if controlPlaneLib ? build then
      controlPlaneLib.build
    else if controlPlaneLib ? getCPM then
      args: { control_plane_model = controlPlaneLib.getCPM args; }
    else if controlPlaneLib ? get_CPM then
      args: { control_plane_model = controlPlaneLib.get_CPM args; }
    else
      throw "network-renderer-nixos: network-control-plane-model.lib is missing build/getCPM/get_CPM";

  built =
    let
      result = builder {
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
}
