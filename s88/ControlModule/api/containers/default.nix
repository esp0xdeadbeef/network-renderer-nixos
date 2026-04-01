{
  lib,
  selectors,
  buildHostFromPaths,
  currentSystem ? builtins.currentSystem,
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

  mergeStringLists = left: right: lib.unique (lib.filter builtins.isString (left ++ right));

  mergeContainerDefaults =
    defaults: container:
    let
      merged = lib.recursiveUpdate defaults container;

      defaultCapabilities =
        if defaults ? additionalCapabilities && builtins.isList defaults.additionalCapabilities then
          defaults.additionalCapabilities
        else
          [ ];

      renderedCapabilities =
        if container ? additionalCapabilities && builtins.isList container.additionalCapabilities then
          container.additionalCapabilities
        else
          [ ];

      defaultAllowedDevices =
        if defaults ? allowedDevices && builtins.isList defaults.allowedDevices then
          defaults.allowedDevices
        else
          [ ];

      renderedAllowedDevices =
        if container ? allowedDevices && builtins.isList container.allowedDevices then
          container.allowedDevices
        else
          [ ];
    in
    merged
    // lib.optionalAttrs (defaultCapabilities != [ ] || renderedCapabilities != [ ]) {
      additionalCapabilities = mergeStringLists defaultCapabilities renderedCapabilities;
    }
    // lib.optionalAttrs (defaultAllowedDevices != [ ] || renderedAllowedDevices != [ ]) {
      allowedDevices = mergeStringLists defaultAllowedDevices renderedAllowedDevices;
    };
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
