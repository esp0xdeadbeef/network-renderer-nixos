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
    file = "s88/Unit/s-router-core/default.nix";
  };
in
{
  _module.args = {
    inherit (queried) fabricInputs globalInventory boxContext;
  };

  imports = [
    "${outPath}/library/10-vms/nixos-shell-vm/host-config-routers-without-network"
    ./fabric-input-loader.nix
    ./host-network
    ./mount-utils.nix
    ./sops.nix
    ./container-settings.nix
  ];
}
