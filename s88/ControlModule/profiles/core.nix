{ pkgs, ... }:

{
  imports = [
    ./common-router.nix
  ];

  environment.systemPackages = with pkgs; [
    tcpdump
  ];
}
