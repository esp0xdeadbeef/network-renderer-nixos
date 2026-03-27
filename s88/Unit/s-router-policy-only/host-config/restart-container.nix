{
  config,
  pkgs,
  lib,
  vmRoot,
  ...
}:
{
  systemd.services."container@${config.networking.hostName}-container".serviceConfig = {
    TasksMax = "infinity";
    TimeoutStartSec = lib.mkForce "15min";
    ExecStartPre = [
      "${pkgs.coreutils}/bin/sleep 10"
    ];
  };

}
