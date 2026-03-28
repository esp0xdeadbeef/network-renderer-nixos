{ ... }:

{
  imports = [
    ./common-router.nix
  ];

  networking.nftables.enable = true;
}
