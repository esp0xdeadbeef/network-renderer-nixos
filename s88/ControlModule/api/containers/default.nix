{
  lib,
  selectors,
  buildHostFromPaths,
  currentSystem ? if builtins ? currentSystem then builtins.currentSystem else "x86_64-linux",
}:

let
  boxInputs = import ../box-build-inputs.nix {
    inherit
      lib
      selectors
      buildHostFromPaths
      currentSystem
      ;
  };

  sortedAttrNames = attrs: lib.sort builtins.lessThan (builtins.attrNames attrs);

  disabledSelectionFrom =
    disabled:
    let
      disabledNames = sortedAttrNames disabled;

      _validateDisabledValues = builtins.foldl' (
        acc: name:
        let
          value = disabled.${name};
        in
        if builtins.isBool value then
          acc
        else
          throw ''
            s88/ControlModule/api/containers/default.nix: disabled entry '${name}' must be a boolean

            value:
            ${builtins.toJSON value}
          ''
      ) true disabledNames;
    in
    builtins.seq _validateDisabledValues (
      builtins.listToAttrs (
        map (name: {
          inherit name;
          value = false;
        }) (lib.filter (name: disabled.${name}) disabledNames)
      )
    );

  inherit (import ../container-defaults.nix { inherit lib; }) mergeContainerDefaults;
in
{
  buildForBox =
    {
      defaults ? { },
      disabled ? { },
      file ? "s88/ControlModule/api/containers/default.nix",
      ...
    }@args:
    let
      resolved = boxInputs.resolve (args // { inherit file; });

      renderedContainers = import ../../render/containers.nix {
        inherit lib;
        hostPlan = resolved.hostPlan;
        cpm = resolved.controlPlaneOut;
        inventory = resolved.globalInventory;
      };

      selectedContainers = import ../container-selection.nix {
        inherit lib;
        containers = renderedContainers;
        containerSelection = disabledSelectionFrom disabled;
      };
    in
    builtins.mapAttrs (_: container: mergeContainerDefaults defaults container) selectedContainers;
}
