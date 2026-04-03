{
  lib,
  pkgs,
  containerModel ? null,
  model ? null,
  ...
}:

let
  resolvedContainerModel =
    if containerModel != null then
      containerModel
    else if model != null then
      model
    else
      throw ''
        s88/ControlModule/access/render/default.nix: requires containerModel
      '';

  advertisementModel = import ../lookup/advertisements.nix {
    inherit
      lib
      ;
    containerModel = resolvedContainerModel;
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
lib.mkMerge modules
