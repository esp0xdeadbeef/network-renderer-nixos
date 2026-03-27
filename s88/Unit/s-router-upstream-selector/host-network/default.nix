{ pkgs, ... }:
{
  imports = [
    ./network-onlymgmt.nix
    ./network.nix
  ];
}
