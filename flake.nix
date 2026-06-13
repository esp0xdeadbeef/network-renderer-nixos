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
    { self
    , nixpkgs
    , nixos-network-compiler
    , network-control-plane-model
    , network-forwarding-model
    , network-labs
    , ...
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

      # NOTE: hostModule previously used buildHostFromPaths with intentPath/inventoryPath.
      # Per FS-310-HDS-010-SDS-010-SMS-100, renderers must consume ONLY CPM output.
      # hostModule now requires pre-built CPM output via the 'cpm' parameter.
      # The pipeline (compiler → NFM → CPM) should run in the host repo or a harness,
      # NOT inside the renderer.
      hostModule =
        { cpm ? null
        , controlPlane ? null
        , hostName
        , system ? null
        , ...
        }@rendererInput:
        { config, lib, pkgs, ... }:
        let
          resolvedSystem = if system != null then system else pkgs.stdenv.hostPlatform.system;
          effectiveCpm = if cpm != null then cpm else controlPlane;
          hostBuild = api.renderer.buildHostFromControlPlane {
            controlPlaneOut =
              if effectiveCpm != null then effectiveCpm
              else throw "network-renderer-nixos hostModule: 'cpm' or 'controlPlane' (control plane model) is required. Per FS-310-HDS-010-SDS-010-SMS-100, renderers consume ONLY CPM output.";
            selector = hostName;
            system = resolvedSystem;
          };
          rendered = hostBuild.renderedHost;
          userLib = rendererInput.lib or lib;

          # Management VLAN2 from CPM deployment hosts (per URS: inventory → CPM → renderer)
          _mgmtDebug = builtins.trace "DEBUG hostName=${hostName} effectiveCpmHasDeploymentHosts=${if effectiveCpm != null && effectiveCpm ? deploymentHosts then "yes" else "no"}" null;
          mgmtHost = builtins.seq _mgmtDebug (if effectiveCpm != null && effectiveCpm ? deploymentHosts then effectiveCpm.deploymentHosts.${hostName} or null else null);
          _mgmtDebug2 = builtins.trace "DEBUG mgmtHostHasUplinks=${if mgmtHost != null && mgmtHost ? uplinks then "yes" else "no"}" null;
          mgmtUplink = builtins.seq _mgmtDebug2 (if mgmtHost != null && mgmtHost ? uplinks then mgmtHost.uplinks.management or null else null);
          _mgmtDebug3 = builtins.trace "DEBUG mgmtUplinkHasVlan=${if mgmtUplink != null && mgmtUplink ? vlan then "yes" else "no"} mgmtUplinkVlan=${if mgmtUplink != null && mgmtUplink ? vlan then toString mgmtUplink.vlan else "null"}" null;
          mgmtVlanId = builtins.seq _mgmtDebug3 (if mgmtUplink != null && mgmtUplink ? vlan then mgmtUplink.vlan else null);
          mgmtNetdevs = if mgmtVlanId != null then {
            "10-eth0.${toString mgmtVlanId}" = {
              netdevConfig = { Name = "eth0.${toString mgmtVlanId}"; Kind = "vlan"; };
              vlanConfig = { Id = mgmtVlanId; };
            };
            "20-vlan${toString mgmtVlanId}" = {
              netdevConfig = { Name = "vlan${toString mgmtVlanId}"; Kind = "bridge"; };
            };
          } else { };
          mgmtNetworks = if mgmtVlanId != null then {
            "10-eth0" = {
              matchConfig.Name = "eth0";
              networkConfig = {
                DHCP = "no"; LinkLocalAddressing = "no";
                VLAN = [ "eth0.${toString mgmtVlanId}" ];
              };
            };
            "20-eth0.${toString mgmtVlanId}" = {
              matchConfig.Name = "eth0.${toString mgmtVlanId}";
              networkConfig = {
                DHCP = "no"; LinkLocalAddressing = "no";
                Bridge = "vlan${toString mgmtVlanId}";
              };
            };
            "30-vlan${toString mgmtVlanId}" = {
              matchConfig.Name = "vlan${toString mgmtVlanId}";
              networkConfig = {
                DHCP = "ipv4"; LinkLocalAddressing = "no";
                IPv6AcceptRA = "no";
              };
            };
          } else { };
        in
        {
          imports = [ hostBuild.artifactModule ];

          networking.useNetworkd = true;
          systemd.network.enable = true;
          networking.useDHCP = false;
          networking.useHostResolvConf = userLib.mkForce false;

          systemd.network.netdevs = userLib.mkMerge [
            (userLib.mkOverride 90 (rendered.netdevs or { }))
            mgmtNetdevs
          ];
          systemd.network.networks = userLib.mkMerge [
            (userLib.mkOverride 90 (rendered.networks or { }))
            mgmtNetworks
          ];
          containers = rendered.containers or { };
        };

      # NOTE: buildVm previously used buildHostFromPaths with intentPath/inventoryPath.
      # Now requires CPM output. Pipeline orchestration belongs in the host repo.
      mkVmApiForSystem =
        system:
        let
          buildVm =
            { cpm ? null
            , boxName
            , simulatedContainerDefaults ? { }
            ,
            }:
            let
              hostBuild = api.renderer.buildHostFromControlPlane {
                controlPlaneOut =
                  if cpm != null then cpm
                  else throw "network-renderer-nixos buildVm: 'cpm' (control plane model) is required.";
                selector = boxName;
                inherit system;
              };

              renderedHost = hostBuild.renderedHost;

              renderedContainersRaw = renderedHost.containers or { };

              renderedContainers = lib.mapAttrs
                (
                  _name: container:
                  simulatedContainerDefaults // (if builtins.isAttrs container then container else { })
                )
                renderedContainersRaw;
            in
            {
              inherit boxName;

              renderedNetdevs = renderedHost.netdevs or { };
              renderedNetworks = renderedHost.networks or { };
              inherit renderedContainers;

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
          renderer = api.renderer // {
            inherit hostModule;
          } // vmApi;
        };
    in
    {
      lib = api // {
        renderer = api.renderer // {
          inherit hostModule;
        };
      };

      libBySystem = forAllSystems mkLibForSystem;

      # NOTE: s88CallFlowEvalTarget removed (CMC-NIXOS-REMOVE-INTENT-INVENTORY).
      # Previously used hardcoded paths to intent.nix and inventory-nixos.nix
      # via buildHostFromPaths. Per SMS-100, renderers must consume CPM output,
      # not discover upstream files from disk.
      packages = forAllSystems (
        system:
        let
          pkgs = import nixpkgs { inherit system; };
          renderDryConfig = import ./s88/Unit/tools/render-dry-config-app.nix {
            inherit pkgs self;
          };
        in
        {
          jq = pkgs.jq;
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
