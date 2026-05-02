{ lib, inventoryModel }:

let
  inherit (inventoryModel) sortedAttrNames;
in
rec {
  inherit sortedAttrNames;

  runtimeTargetForUnitFromNormalized =
    { normalizedRuntimeTargets, unitName, file ? "s88/Unit/physical/realization-ports.nix" }:
    if builtins.hasAttr unitName normalizedRuntimeTargets then
      normalizedRuntimeTargets.${unitName}
    else
      throw ''
        ${file}: missing normalized runtime target for unit '${unitName}'
      '';

  runtimeLogicalNodeForUnitFromNormalized =
    args:
    let
      runtimeTarget = runtimeTargetForUnitFromNormalized args;
    in
    if runtimeTarget ? logicalNode && builtins.isAttrs runtimeTarget.logicalNode then
      runtimeTarget.logicalNode
    else
      { };

  lastStringSegment =
    separator: value:
    let
      pieces = lib.splitString separator value;
      count = builtins.length pieces;
    in
    if count == 0 then null else builtins.elemAt pieces (count - 1);

  collapseRepeatedTrailingDashSegment =
    value:
    let
      pieces = lib.splitString "-" value;
      count = builtins.length pieces;
      last = if count >= 1 then builtins.elemAt pieces (count - 1) else null;
      prev = if count >= 2 then builtins.elemAt pieces (count - 2) else null;
    in
    if count >= 2 && last == prev then
      builtins.concatStringsSep "-" (lib.take (count - 1) pieces)
    else
      value;
}
