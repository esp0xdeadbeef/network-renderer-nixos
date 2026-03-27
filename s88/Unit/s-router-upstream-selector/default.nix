{
  outPath,
  lib,
  config,
  pkgs,
  inputs,
  ...
}:

let
  queried = inputs."network-renderer-nixos".lib.queryBox.queryFromOutPath {
    inherit outPath;
    hostname = config.networking.hostName;
    file = "s88/Unit/s-router-upstream-selector/default.nix";
  };
in
{
  imports = [
    "${outPath}/library/10-vms/nixos-shell-vm/host-config-routers-without-network"
    ./host-network
    ./mount-utils.nix
    ./sops.nix
    ./container-settings.nix
    ./fabric-input-loader.nix
  ];

  _module.args = {
    inherit (queried) fabricInputs globalInventory boxContext;
  };
}
