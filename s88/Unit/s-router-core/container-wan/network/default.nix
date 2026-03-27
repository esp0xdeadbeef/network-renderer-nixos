{ pkgs, ... }:
{
  imports = [
    ./wan.nix
    ./link-to-policy.nix
    ./general.nix
  ];
}
