{ lib
, pkgs
, containerName
, renderedModel
, alarmModel
,
}:

let
  debugTools = import ../../../debug-tools.nix { inherit pkgs; };
  usesOnlyExtraVeths =
    !(builtins.isString (renderedModel.hostBridge or null) && renderedModel.hostBridge != "");
in
{
  imports = lib.optionals (renderedModel ? profilePath && renderedModel.profilePath != null) [
    renderedModel.profilePath
  ];

  resolvedHostName =
    if renderedModel ? unitName && builtins.isString renderedModel.unitName then renderedModel.unitName else containerName;

  warningMessages =
    if alarmModel ? warningMessages && builtins.isList alarmModel.warningMessages then
      lib.unique (lib.filter builtins.isString alarmModel.warningMessages)
    else
      [ ];

  commonRouterConfig = {
    boot.isContainer = true;
    networking.useNetworkd = true;
    systemd.network.enable = true;
    systemd.services.systemd-networkd-wait-online.enable = lib.mkIf usesOnlyExtraVeths (lib.mkForce false);
    networking.useDHCP = false;
    networking.networkmanager.enable = false;
    networking.useHostResolvConf = lib.mkForce false;
    services.resolved.enable = lib.mkForce false;
    networking.firewall.enable = lib.mkForce false;
    environment.systemPackages = debugTools;
    system.stateVersion = "25.11";
  };
}
