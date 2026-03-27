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
    file = "s88/Unit/s-router-access/default.nix";
  };
in
{
  imports = [
    "${outPath}/library/10-vms/nixos-shell-vm/host-config-routers-without-network"
    ./fabric-input-loader.nix
    ./host-network.nix
    ./mount-utils.nix
    ./container/container-settings.nix
    ./debugging-packages.nix
    ./sops.nix
  ];

  _module.args = {
    inherit (queried) fabricInputs globalInventory boxContext;
  };
}
