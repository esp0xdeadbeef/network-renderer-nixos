{ pkgs, ... }:
{
  imports = [
    ./wan.nix
    ./fabric.nix
    ./general.nix
  ];
}
