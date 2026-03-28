{ lib, s88Role, ... }:

{
  imports =
    [
      ./fabric-input-loader.nix
      ./host-network.nix
    ]
    ++ lib.optionals ((s88Role.container.enable or false)) [
      ./container-runtime.nix
    ];
}
