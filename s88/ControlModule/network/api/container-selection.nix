{
  lib,
  containers ? { },
  containerSelection ? { },
}:

let
  sortedAttrNames = attrs: lib.sort builtins.lessThan (builtins.attrNames attrs);

  selectionNames = sortedAttrNames containerSelection;

  _validateSelectionValues = builtins.foldl' (
    acc: name:
    let
      value = containerSelection.${name};
    in
    if builtins.isBool value then
      acc
    else
      throw ''
        s88/ControlModule/network/api/container-selection.nix: containerSelection entry '${name}' must be a boolean

        value:
        ${builtins.toJSON value}
      ''
  ) true selectionNames;

  containerNames = sortedAttrNames containers;

  enabledNames = lib.filter (name: containerSelection.${name}) selectionNames;
  disabledNames = lib.filter (name: !containerSelection.${name}) selectionNames;

  selectedNames =
    if containerSelection == { } then
      containerNames
    else if enabledNames != [ ] then
      lib.filter (name: builtins.elem name enabledNames) containerNames
    else
      lib.filter (name: !(builtins.elem name disabledNames)) containerNames;
in
builtins.seq _validateSelectionValues (
  builtins.listToAttrs (
    map (name: {
      inherit name;
      value = containers.${name};
    }) selectedNames
  )
)
