{
  lib,
  pkgs,
  containerModel,
}:

let
  advertisementModel = import ../lookup/advertisements.nix {
    inherit
      lib
      containerModel
      ;
  };

  modules =
    (map (
      scope:
      import ./kea.nix {
        inherit
          lib
          pkgs
          scope
          ;
      }
    ) advertisementModel.dhcp4Scopes)
    ++ (map (
      scope:
      import ./radvd.nix {
        inherit
          lib
          pkgs
          scope
          ;
      }
    ) advertisementModel.radvdScopes);
in
lib.mkMerge (
  modules
  ++ [
    {
      warnings = advertisementModel.warnings;
    }
  ]
)
