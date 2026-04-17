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

      mkSystemLib =
        system:
        let
          api = mkApi system;

          controlPlaneLib =
            if network-control-plane-model ? libBySystem then
              network-control-plane-model.libBySystem.${system}
            else
              network-control-plane-model.lib.${system};
        in
        api
        // {
          controlPlane = controlPlaneLib;
          writeControlPlaneJSON = controlPlaneLib.writeCompileAndBuildJSON;
          compileAndBuildControlPlane = controlPlaneLib.compileAndBuild;
          compileAndBuildControlPlaneFromPaths = controlPlaneLib.compileAndBuildFromPaths;
        };

      defaultSystem = if builtins ? currentSystem then builtins.currentSystem else "x86_64-linux";
    in
    {
      lib = mkSystemLib defaultSystem;
      libBySystem = forAll mkSystemLib;
    };
}
