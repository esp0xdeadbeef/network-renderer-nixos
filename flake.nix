{
  description = "Shared NixOS network renderer helpers and router units";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  };

  outputs = { self, nixpkgs, ... }:
    let
      lib = nixpkgs.lib;

      mkUnit = path: {
        inherit path;
        module = import path;
      };
    in
    {
      lib = {
        queryBox = import ./lib/query-box.nix { inherit lib; };
      };

      s88 = {
        Unit = {
          "s-router-access" = mkUnit ./s88/Unit/s-router-access;
          "s-router-core" = mkUnit ./s88/Unit/s-router-core;
          "s-router-policy-only" = mkUnit ./s88/Unit/s-router-policy-only;
          "s-router-upstream-selector" = mkUnit ./s88/Unit/s-router-upstream-selector;
        };
      };

      nixosModules = {
        "s-router-access" = import ./s88/Unit/s-router-access;
        "s-router-core" = import ./s88/Unit/s-router-core;
        "s-router-policy-only" = import ./s88/Unit/s-router-policy-only;
        "s-router-upstream-selector" = import ./s88/Unit/s-router-upstream-selector;
      };
    };
}
