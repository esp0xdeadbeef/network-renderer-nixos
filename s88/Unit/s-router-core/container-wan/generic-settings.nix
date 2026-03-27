{ pkgs, lib, ... }:
{
  system.stateVersion = "25.11";
  services.dbus.enable = true;
}
