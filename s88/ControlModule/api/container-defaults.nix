{ lib }:

let
  mergeStringLists = left: right: lib.unique (lib.filter builtins.isString (left ++ right));
in
{
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
}
