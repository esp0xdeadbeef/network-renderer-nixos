{
  lib,
  debugEnabled ? false,
  deploymentHostName,
  containerName,
  renderedModel,
  firewallArg,
  alarmModel,
  uplinks,
  wanUplinkName,
}:

let
  uniqueStrings = values: lib.unique (lib.filter builtins.isString values);

  warningMessages =
    if alarmModel ? warningMessages && builtins.isList alarmModel.warningMessages then
      uniqueStrings alarmModel.warningMessages
    else
      [ ];

  alarms =
    if alarmModel ? alarms && builtins.isList alarmModel.alarms then alarmModel.alarms else [ ];

  containerConfigModule = import ./module.nix {
    inherit
      lib
      containerName
      renderedModel
      firewallArg
      alarmModel
      uplinks
      wanUplinkName
      ;
  };
in
{
  autoStart =
    if renderedModel ? autoStart && builtins.isBool renderedModel.autoStart then
      renderedModel.autoStart
    else
      true;

  privateNetwork = true;

  hostBridge =
    if renderedModel ? hostBridge && builtins.isString renderedModel.hostBridge then
      renderedModel.hostBridge
    else
      null;

  bindMounts =
    if renderedModel ? bindMounts && builtins.isAttrs renderedModel.bindMounts then
      renderedModel.bindMounts
    else
      { };

  extraVeths = renderedModel.veths or { };

  allowedDevices = uniqueStrings (
    if renderedModel ? allowedDevices && builtins.isList renderedModel.allowedDevices then
      renderedModel.allowedDevices
    else
      [ ]
  );

  additionalCapabilities = uniqueStrings (
    [
      "CAP_NET_ADMIN"
      "CAP_NET_RAW"
    ]
    ++ (
      if
        renderedModel ? additionalCapabilities && builtins.isList renderedModel.additionalCapabilities
      then
        renderedModel.additionalCapabilities
      else
        [ ]
    )
  );

  config = containerConfigModule;

  specialArgs = {
    inherit deploymentHostName;
    s88RoleName = renderedModel.roleName or null;
    s88Firewall = firewallArg;
    s88Warnings = warningMessages;
    s88Alarms = alarms;
    unitName =
      if renderedModel ? unitName && builtins.isString renderedModel.unitName then
        renderedModel.unitName
      else
        containerName;
  }
  // lib.optionalAttrs debugEnabled {
    s88Debug = renderedModel;
  };
}
