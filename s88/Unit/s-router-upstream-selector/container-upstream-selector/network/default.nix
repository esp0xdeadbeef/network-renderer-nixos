{ pkgs, ... }:
{
  imports = [
    ./p2p-to-core.nix
    ./link-to-policy.nix
    ./general.nix
  ];
}
