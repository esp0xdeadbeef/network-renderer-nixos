{ lib }:

let
  mergeStringLists = left: right: lib.unique (lib.filter builtins.isString (left ++ right));

  allowedDeviceKey =
    device:
    if builtins.isString device then
      device
    else if builtins.isAttrs device && builtins.isString (device.node or null) then
      device.node
    else
      "";

  mergeAllowedDevices =
    left: right:
    let
      devices = lib.filter (device: allowedDeviceKey device != "") (left ++ right);
      keyed = map (device: {
        name = allowedDeviceKey device;
        value = device;
      }) devices;
    in
    builtins.attrValues (builtins.listToAttrs keyed);
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
      allowedDevices = mergeAllowedDevices defaultAllowedDevices renderedAllowedDevices;
    };
}
