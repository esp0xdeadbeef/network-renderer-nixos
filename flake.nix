{
  description = "network-renderer-nixos";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

    network-control-plane-model.url = "github:esp0xdeadbeef/network-control-plane-model";
    network-control-plane-model.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs =
    {
      self,
      nixpkgs,
      network-control-plane-model,
    }:
    let
      systems = [
        "x86_64-linux"
        "aarch64-linux"
      ];

      forAll = f: nixpkgs.lib.genAttrs systems f;

      mkPkgs = system: import nixpkgs { inherit system; };

      mkApi =
        system:
        let
          pkgs = mkPkgs system;
        in
        import ./src/api/default.nix {
          lib = pkgs.lib;
          controlPlaneLib = network-control-plane-model.lib.${system};
        };

      defaultSystem = if builtins ? currentSystem then builtins.currentSystem else "x86_64-linux";
    in
    {
      lib = mkApi defaultSystem;
      libBySystem = forAll mkApi;
    };
}
