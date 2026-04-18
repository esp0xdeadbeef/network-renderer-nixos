{
  description = "network-renderer-nixos";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

    nixos-network-compiler.url = "github:esp0xdeadbeef/nixos-network-compiler";

    network-control-plane-model.url = "github:esp0xdeadbeef/network-control-plane-model";

    network-forwarding-model.url = "github:esp0xdeadbeef/network-forwarding-model";
    network-forwarding-model.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs =
    {
      self,
      nixpkgs,
      nixos-network-compiler,
      network-control-plane-model,
      network-forwarding-model,
      ...
    }:
    let
      lib = nixpkgs.lib;
      systems = [
        "x86_64-linux"
        "aarch64-linux"
      ];
      forAllSystems = lib.genAttrs systems;

      api = import ./s88/Enterprise/default.nix {
        inherit lib;
        repoRoot = ./.;
        flakeInputs = {
          inherit
            nixpkgs
            nixos-network-compiler
            network-control-plane-model
            network-forwarding-model
            ;
        };
      };
    in
    {
      lib = api;

      packages = forAllSystems (
        system:
        let
          pkgs = import nixpkgs { inherit system; };
          renderDryConfig = import ./s88/ControlModule/tools/render-dry-config-app.nix {
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
