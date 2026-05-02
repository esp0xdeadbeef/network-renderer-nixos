{ lib }:

let
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
            s88/Unit/api/host-selection.nix: disabled entry '${name}' must be a boolean

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

  selectedContainersForHost =
    {
      containerDefaults,
      containerSelection,
      renderedHost,
      mergeContainerDefaults,
    }:
    let
      selectedContainers = import ../../ControlModule/api/container-selection.nix {
        inherit
          lib
          containerSelection
          ;
        containers = renderedHost.containers or { };
      };
    in
    renderedHost
    // {
      containers = builtins.mapAttrs (
        _: container: mergeContainerDefaults containerDefaults container
      ) selectedContainers;
    };
in
{
  inherit disabledSelectionFrom selectedContainersForHost;
}
