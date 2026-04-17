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

      mkVmSystem =
        system:
        nixpkgs.lib.nixosSystem {
          inherit system;
          modules = [ ./vm.nix ];
        };

      mkVmRunner =
        system:
        let
          pkgs = mkPkgs system;
          vmSystem = mkVmSystem system;
        in
        pkgs.writeShellScriptBin "network-renderer-nixos-vm" ''
          set -euo pipefail

          vm_bin_dir="${vmSystem.config.system.build.vm}/bin"
          runner="$(find "$vm_bin_dir" -maxdepth 1 -type f -name 'run-*-vm' | head -n 1)"

          if [ -z "$runner" ]; then
            echo "network-renderer-nixos: no VM runner found in $vm_bin_dir" >&2
            exit 1
          fi

          exec "$runner" "$@"
        '';

      defaultSystem = if builtins ? currentSystem then builtins.currentSystem else "x86_64-linux";
    in
    {
      lib = mkSystemLib defaultSystem;
      libBySystem = forAll mkSystemLib;

      nixosConfigurations = forAll mkVmSystem;

      packages = forAll (
        system:
        let
          vmSystem = mkVmSystem system;
        in
        {
          vm = vmSystem.config.system.build.vm;
          vm-runner = mkVmRunner system;
        }
      );

      apps = forAll (system: {
        vm = {
          type = "app";
          program = "${self.packages.${system}.vm-runner}/bin/network-renderer-nixos-vm";
        };
      });
    };
}
