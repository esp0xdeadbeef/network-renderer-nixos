{
  description = "network-renderer-nixos";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

    nixos-network-compiler.url = "github:esp0xdeadbeef/nixos-network-compiler";

    network-control-plane-model.url = "github:esp0xdeadbeef/network-control-plane-model";

    network-forwarding-model.url = "github:esp0xdeadbeef/network-forwarding-model";
    network-forwarding-model.inputs.nixpkgs.follows = "nixpkgs";

    network-labs.url = "github:esp0xdeadbeef/network-labs";
  };

  outputs =
    {
      self,
      nixpkgs,
      nixos-network-compiler,
      network-control-plane-model,
      network-forwarding-model,
      network-labs,
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

      mkVmApiForSystem =
        system:
        let
          buildVm =
            {
              intentPath,
              inventoryPath,
              boxName,
              simulatedContainerDefaults ? { },
            }:
            let
              hostBuild = api.renderer.buildHostFromPaths {
                selector = boxName;
                inherit intentPath inventoryPath system;
              };

              renderedHost = hostBuild.renderedHost;

              renderedContainersRaw = renderedHost.containers or { };

              renderedContainers = lib.mapAttrs (
                _name: container:

                simulatedContainerDefaults // (if builtins.isAttrs container then container else { })
              ) renderedContainersRaw;
            in
            {
              inherit boxName;

              renderedNetdevs = renderedHost.netdevs or { };
              renderedNetworks = renderedHost.networks or { };
              renderedContainers = renderedContainers;

              inherit (hostBuild) compilerOut forwardingOut controlPlaneOut;

              artifactModule =
                { ... }:
                {
                  environment.etc."network-artifacts/compiler.json".text = builtins.toJSON hostBuild.compilerOut;
                  environment.etc."network-artifacts/forwarding.json".text = builtins.toJSON hostBuild.forwardingOut;
                  environment.etc."network-artifacts/control-plane.json".text =
                    builtins.toJSON hostBuild.controlPlaneOut;
                };
            };
        in
        {
          vm = {
            build = buildVm;
          };
        };

      mkLibForSystem =
        system:
        let
          vmApi = mkVmApiForSystem system;
        in
        api
        // vmApi
        // {

          renderer = api.renderer // vmApi;
        };
    in
    {
      lib = api;
      libBySystem = forAllSystems mkLibForSystem;

      packages = forAllSystems (
        system:
        let
          pkgs = import nixpkgs { inherit system; };
          renderDryConfig = import ./s88/Unit/tools/render-dry-config-app.nix {
            inherit pkgs self;
          };
          s88CallFlowEvalTarget =
            let
              hostBuild = api.renderer.buildHostFromPaths {
                system = system;
                selector = "s-router-hetzner-anywhere";
                intentPath = network-labs.outPath + "/examples/s-router-overlay-dns-lane-policy/intent.nix";
                inventoryPath = network-labs.outPath + "/examples/s-router-overlay-dns-lane-policy/inventory-nixos.nix";
              };
            in
            pkgs.writeText "s88-call-flow-eval-target.json" (
              builtins.toJSON {
                selectedUnits = hostBuild.selectedUnits or [ ];
                renderedContainerNames = lib.sort builtins.lessThan (
                  builtins.attrNames (hostBuild.renderedHost.containers or { })
                );
              }
            );
        in
        {
          jq = pkgs.jq;
          render-dry-config = renderDryConfig;
          s88-call-flow-eval-target = s88CallFlowEvalTarget;
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
