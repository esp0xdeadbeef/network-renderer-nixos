{ lib, ... }:

{
  hostBridges = import ../mapping/host-bridges.nix { inherit lib; };
  wanAttachment = import ../mapping/wan-attachment.nix { inherit lib; };
  transitBridges = import ../physical/transit-bridges.nix { inherit lib; };
}
