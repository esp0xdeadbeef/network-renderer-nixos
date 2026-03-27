{ pkgs, ... }:
{
  imports = [
    ./network
    ./nftables.nix
    ./firewall.nix
    ./kernel-flags.nix
    ./debugging-packages.nix
    ./generic-settings.nix
  ];
}
