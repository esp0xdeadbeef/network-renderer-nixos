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
          renderedNetdevs = rendered.netdevs or { };
          renderedNetworks = rendered.networks or { };
          userLib = rendererInput.lib or lib;

          # Management networking from CPM deployment hosts (per URS: inventory → CPM → renderer).
          # Supports two modes:
          #   mode=vlan: VLAN-tagged management (lab hosts) — creates VLAN subinterface + bridge + DHCP
          #   mode=native: native DHCP on physical interface (cloud hosts) — DHCP directly on eth0
          mgmtHost = if effectiveCpm != null && effectiveCpm ? deploymentHosts then effectiveCpm.deploymentHosts.${hostName} or null else null;
          mgmtUplink = if mgmtHost != null && mgmtHost ? uplinks then mgmtHost.uplinks.management or null else null;
          mgmtMode = if mgmtUplink != null && mgmtUplink ? mode then mgmtUplink.mode else null;
          mgmtParent = if mgmtUplink != null && mgmtUplink ? parent then mgmtUplink.parent else null;
          mgmtVlanId = if mgmtMode == "vlan" && mgmtUplink ? vlan then mgmtUplink.vlan else null;

          # CPM-driven: does the management uplink request DHCP via the renderer?
          mgmtIpv4 = if mgmtUplink != null && mgmtUplink ? ipv4 then mgmtUplink.ipv4 else null;
          mgmtManageDhcp = mgmtIpv4 != null && (mgmtIpv4.enable or false) == true;

          # Hard-fail on missing or inconsistent management configuration.
          # Every host must have a management uplink with mode, parent, and DHCP config.
          mgmtValidate = if mgmtManageDhcp then
            if mgmtMode == null then
              throw "network-renderer-nixos: host ${hostName} management uplink has ipv4.enable=true but no 'mode' field (must be 'vlan' or 'native')"
            else if mgmtParent == null then
              throw "network-renderer-nixos: host ${hostName} management uplink has ipv4.enable=true but no 'parent' field (must be the physical interface name, e.g. 'eth0' or 'enp1s0')"
            else if mgmtMode == "vlan" && mgmtVlanId == null then
              throw "network-renderer-nixos: host ${hostName} management uplink mode=vlan but no 'vlan' field"
            else null
          else null;

          renderedHasMgmtVlan =
            mgmtVlanId != null
            && builtins.hasAttr "11-${mgmtParent}.${toString mgmtVlanId}" renderedNetdevs
            && builtins.hasAttr "20-${mgmtParent}" renderedNetworks
            && builtins.hasAttr "21-${mgmtParent}.${toString mgmtVlanId}" renderedNetworks
            && builtins.hasAttr "30-vlan${toString mgmtVlanId}" renderedNetworks;

          renderedHasNativeMgmt =
            mgmtManageDhcp
            && mgmtMode == "native"
            && mgmtParent != null
            && builtins.hasAttr "20-${mgmtParent}" renderedNetworks;

          # VLAN mode: create VLAN subinterface + bridge, DHCP on bridge
          legacyMgmtNetdevs = if mgmtVlanId != null then {
            "10-${mgmtParent}.${toString mgmtVlanId}" = {
              netdevConfig = { Name = "${mgmtParent}.${toString mgmtVlanId}"; Kind = "vlan"; };
              vlanConfig = { Id = mgmtVlanId; };
            };
            "20-vlan${toString mgmtVlanId}" = {
              netdevConfig = { Name = "vlan${toString mgmtVlanId}"; Kind = "bridge"; };
            };
          } else { };

          legacyMgmtNetworks = if mgmtVlanId != null then {
            "10-${mgmtParent}" = {
              matchConfig.Name = mgmtParent;
              networkConfig = {
                DHCP = "no"; LinkLocalAddressing = "no";
                VLAN = [ "${mgmtParent}.${toString mgmtVlanId}" ];
              };
            };
            "20-${mgmtParent}.${toString mgmtVlanId}" = {
              matchConfig.Name = "${mgmtParent}.${toString mgmtVlanId}";
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
          } else if mgmtManageDhcp && mgmtMode == "native" && mgmtParent != null then {
            # Native mode: DHCP directly on the physical interface
            "10-${mgmtParent}" = {
              matchConfig.Name = mgmtParent;
              networkConfig = {
                DHCP = "ipv4";
                LinkLocalAddressing = "no";
                IPv6AcceptRA = "no";
              };
            };
          } else { };

          mgmtNetdevs =
            if renderedHasMgmtVlan then
              { }
            else
              legacyMgmtNetdevs;

          mgmtNetworks =
            if renderedHasMgmtVlan || renderedHasNativeMgmt then
              { }
            else
              legacyMgmtNetworks;
        in
        {
          imports = [ hostBuild.artifactModule ];

          # CPM-driven networking: only override host DHCP/networkd when
          # management uplink requests it (ipv4.enable = true).
          networking.useNetworkd = lib.mkIf mgmtManageDhcp true;
          systemd.network.enable = lib.mkIf mgmtManageDhcp true;
          networking.useDHCP = lib.mkIf mgmtManageDhcp false;
          networking.useHostResolvConf = userLib.mkForce false;

          systemd.network.netdevs = renderedNetdevs // mgmtNetdevs;
          systemd.network.networks = renderedNetworks // mgmtNetworks;
          containers = rendered.containers or { };

          # GAMP: FS-840 — scoped runtime secret delivery: containers with
          # bind mounts to /run/secrets/ must wait for sops-nix.service.
          systemd.services = builtins.listToAttrs (map
            (name: {
              name = "container@${name}";
              value = {
                after = [ "sops-nix.service" ];
              };
            })
            (builtins.attrNames (rendered.containers or { })));
        }
        // builtins.seq mgmtValidate { };

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
