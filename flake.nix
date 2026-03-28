{
  description = "network-renderer-nixos";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs =
    { self, nixpkgs, ... }:
    let
      lib = nixpkgs.lib;
      systems = [
        "x86_64-linux"
        "aarch64-linux"
      ];
      forAllSystems = lib.genAttrs systems;
      api = import ./lib/api.nix { inherit lib; };
    in
    {
      lib = api;

      packages = forAllSystems (
        system:
        let
          pkgs = import nixpkgs { inherit system; };
          renderDryConfig = import ./lib/render-dry-config-app.nix {
            inherit pkgs self;
          };
        in
        {
          render-dry-config = renderDryConfig;
          default = renderDryConfig;
        }
      );

      apps = forAllSystems (
        system:
        let
          program = "${self.packages.${system}.render-dry-config}/bin/render-dry-config";
        in
        {
          render-dry-config = {
            type = "app";
            inherit program;
          };

          default = {
            type = "app";
            inherit program;
          };
        }
      );
    };
}
