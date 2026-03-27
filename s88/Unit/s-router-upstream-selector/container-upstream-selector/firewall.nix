{ pkgs, lib, ... }:
{
  networking.firewall.enable = false;

  networking.nftables = {
    enable = true;
    ruleset = builtins.readFile ./nftables.nft;
  };
}
