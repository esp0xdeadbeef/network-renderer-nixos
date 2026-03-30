{
  lib,
  containers ? { },
  containerSelection ? { },
}:

let
  sortedAttrNames = attrs: lib.sort builtins.lessThan (builtins.attrNames attrs);

  selectionNames = sortedAttrNames containerSelection;
  containerNames = sortedAttrNames containers;

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

  aliasesForContainer =
    containerName:
    let
      container = containers.${containerName};
      unitName =
        if
          container ? specialArgs
          && builtins.isAttrs container.specialArgs
          && container.specialArgs ? unitName
          && builtins.isString container.specialArgs.unitName
        then
          container.specialArgs.unitName
        else
          null;
    in
    lib.unique (
      lib.filter builtins.isString [
        containerName
        unitName
      ]
    );

  aliasMatchesSelector =
    selector: alias:
    alias == selector || lib.hasSuffix "-${selector}" alias || lib.hasSuffix "::${selector}" alias;

  containerMatchesSelector =
    selector: containerName:
    lib.any (alias: aliasMatchesSelector selector alias) (aliasesForContainer containerName);

  resolveSelector =
    selector:
    let
      matches = lib.filter (
        containerName: containerMatchesSelector selector containerName
      ) containerNames;
    in
    if matches == [ ] then
      throw ''
        s88/ControlModule/network/api/container-selection.nix: selector '${selector}' did not match any rendered container

        available container names:
        ${builtins.toJSON containerNames}
      ''
    else if builtins.length matches == 1 then
      builtins.head matches
    else
      throw ''
        s88/ControlModule/network/api/container-selection.nix: selector '${selector}' matched multiple rendered containers

        matches:
        ${builtins.toJSON matches}
      '';

  enabledSelectors = lib.filter (name: containerSelection.${name}) selectionNames;
  disabledSelectors = lib.filter (name: !containerSelection.${name}) selectionNames;

  enabledContainerNames = map resolveSelector enabledSelectors;
  disabledContainerNames = map resolveSelector disabledSelectors;

  selectedNames =
    if containerSelection == { } then
      containerNames
    else
      lib.filter (name: !(builtins.elem name disabledContainerNames)) (
        if enabledSelectors != [ ] then enabledContainerNames else containerNames
      );
in
builtins.seq _validateSelectionValues (
  builtins.listToAttrs (
    map (name: {
      inherit name;
      value = containers.${name};
    }) selectedNames
  )
)
