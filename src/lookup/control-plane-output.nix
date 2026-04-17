{
  lib,
  controlPlaneLib,
  importValue,
}:
{
  intentPath ? null,
  inventoryPath ? null,
  intent ? null,
  inventory ? null,
}:
let
  _requireIntentSource =
    if intent != null || intentPath != null then
      true
    else
      throw "network-renderer-nixos: buildControlPlaneOutput requires either intent or intentPath";

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

  sanitizeForJson =
    value:
    let
      valueType = builtins.typeOf value;
    in
    if valueType == "lambda" then
      null
    else if valueType == "set" then
      builtins.listToAttrs (
        lib.concatMap (
          name:
          let
            child = sanitizeForJson value.${name};
          in
          if child == null then
            [ ]
          else
            [
              {
                inherit name;
                value = child;
              }
            ]
        ) (builtins.attrNames value)
      )
    else if valueType == "list" then
      lib.concatMap (
        child:
        let
          normalized = sanitizeForJson child;
        in
        if normalized == null then [ ] else [ normalized ]
      ) value
    else if valueType == "path" then
      toString value
    else
      value;

  builtRaw =
    let
      result =
        if
          intent != null
          || inventory != null
          || intentPath == null
          || !(controlPlaneLib ? compileAndBuildFromPaths)
        then
          buildFromValues {
            input = resolvedIntent;
            inventory = resolvedInventory;
          }
        else
          controlPlaneLib.compileAndBuildFromPaths {
            inputPath = intentPath;
            inherit inventoryPath;
          };
    in
    if builtins.isAttrs result then result else { control_plane_model = result; };

  built = sanitizeForJson builtRaw;
in
builtins.seq _requireIntentSource (
  built
  // {
    fabricInputs = sanitizeForJson resolvedIntent;
    globalInventory = sanitizeForJson resolvedInventory;
    inventory = sanitizeForJson resolvedInventory;
  }
)
