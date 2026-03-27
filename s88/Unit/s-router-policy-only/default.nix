{
  outPath,
  lib,
  config,
  inputs,
  ...
}:

let
  queried = inputs."network-renderer-nixos".lib.queryBox.queryFromOutPath {
    inherit outPath;
    hostname = config.networking.hostName;
    file = "s88/Unit/s-router-policy-only/default.nix";
  };
in
{
  _module.args = {
    inherit (queried) fabricInputs globalInventory boxContext;
  };

  imports = [
    ./host-config
    ./fabric-input-loader.nix
    ./mount-utils.nix
    ./container-settings.nix
    ./nftables.nix
    ./debugging-packages.nix
  ];

  networking.useNetworkd = true;
  systemd.network.enable = true;
  networking.useDHCP = false;

  system.stateVersion = "25.11";
}
