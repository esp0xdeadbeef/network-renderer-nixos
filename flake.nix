{
  description = "network-renderer-nixos";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

    nixos-network-compiler.url = "github:esp0xdeadbeef/nixos-network-compiler";

    network-control-plane-model.url = "github:esp0xdeadbeef/network-control-plane-model";

    network-forwarding-model.url = "github:esp0xdeadbeef/network-forwarding-model";
    network-forwarding-model.inputs.nixpkgs.follows = "nixpkgs";

    network-realization-model.url = "github:esp0xdeadbeef/network-realization-model";
    network-realization-model.inputs.nixpkgs.follows = "nixpkgs";

    network-labs.url = "github:esp0xdeadbeef/network-labs";
  };

  outputs =
    {
      self,
      nixpkgs,
      nixos-network-compiler,
      network-control-plane-model,
      network-forwarding-model,
      network-realization-model,
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

      hostModule =
        {
          cpm ? null,
          controlPlane ? null,
          hostName,
          system ? null,
          ...
        }@rendererInput:
        {
          config,
          lib,
          pkgs,
          ...
        }:
        let
          resolvedSystem = if system != null then system else pkgs.stdenv.hostPlatform.system;
          effectiveCpm = if cpm != null then cpm else controlPlane;
          artifactCompilerOut =
            if rendererInput ? compilerOut then
              rendererInput.compilerOut
            else if effectiveCpm != null && builtins.isAttrs effectiveCpm && effectiveCpm ? compilerOut then
              effectiveCpm.compilerOut
            else
              null;
          artifactForwardingOut =
            if rendererInput ? forwardingOut then
              rendererInput.forwardingOut
            else if effectiveCpm != null && builtins.isAttrs effectiveCpm && effectiveCpm ? forwardingOut then
              effectiveCpm.forwardingOut
            else
              null;
          hostBuild = api.renderer.buildHostFromControlPlane {
            controlPlaneOut =
              if effectiveCpm != null then
                effectiveCpm
              else
                throw "network-renderer-nixos hostModule: 'cpm' or 'controlPlane' (control plane model) is required. Per FS-310-HDS-010-SDS-010-SMS-100, renderers consume ONLY CPM output.";
            selector = hostName;
            system = resolvedSystem;
            compilerOut = artifactCompilerOut;
            forwardingOut = artifactForwardingOut;
          };
          rendered = hostBuild.renderedHost;
          renderedNetdevs = rendered.netdevs or { };
          renderedNetworks = rendered.networks or { };
          renderedContainers = rendered.containers or { };
          requiresNetworkd = import ./s88/ControlModule/render/host-networkd-requirement.nix { };
          userLib = rendererInput.lib or lib;

          mgmtHost =
            if effectiveCpm != null && effectiveCpm ? deploymentHosts then
              effectiveCpm.deploymentHosts.${hostName} or null
            else
              null;
          mgmtUplink =
            if mgmtHost != null && mgmtHost ? uplinks then mgmtHost.uplinks.management or null else null;
          mgmtMode = if mgmtUplink != null && mgmtUplink ? mode then mgmtUplink.mode else null;
          mgmtParent = if mgmtUplink != null && mgmtUplink ? parent then mgmtUplink.parent else null;
          mgmtVlanId = if mgmtMode == "vlan" && mgmtUplink ? vlan then mgmtUplink.vlan else null;

          mgmtIpv4 = if mgmtUplink != null && mgmtUplink ? ipv4 then mgmtUplink.ipv4 else null;
          mgmtManageDhcp = mgmtIpv4 != null && (mgmtIpv4.enable or false) == true;

          mgmtValidate =
            if mgmtManageDhcp then
              if mgmtMode == null then
                throw "network-renderer-nixos: host ${hostName} management uplink has ipv4.enable=true but no 'mode' field (must be 'vlan' or 'native')"
              else if mgmtParent == null then
                throw "network-renderer-nixos: host ${hostName} management uplink has ipv4.enable=true but no 'parent' field (must be the physical interface name, e.g. 'eth0' or 'enp1s0')"
              else if mgmtMode == "vlan" && mgmtVlanId == null then
                throw "network-renderer-nixos: host ${hostName} management uplink mode=vlan but no 'vlan' field"
              else
                null
            else
              null;

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

          legacyMgmtNetdevs =
            if mgmtVlanId != null then
              {
                "10-${mgmtParent}.${toString mgmtVlanId}" = {
                  netdevConfig = {
                    Name = "${mgmtParent}.${toString mgmtVlanId}";
                    Kind = "vlan";
                  };
                  vlanConfig = {
                    Id = mgmtVlanId;
                  };
                };
                "20-vlan${toString mgmtVlanId}" = {
                  netdevConfig = {
                    Name = "vlan${toString mgmtVlanId}";
                    Kind = "bridge";
                  };
                };
              }
            else
              { };

          legacyMgmtNetworks =
            if mgmtVlanId != null then
              {
                "10-${mgmtParent}" = {
                  matchConfig.Name = mgmtParent;
                  networkConfig = {
                    DHCP = "no";
                    LinkLocalAddressing = "no";
                    VLAN = [ "${mgmtParent}.${toString mgmtVlanId}" ];
                  };
                };
                "20-${mgmtParent}.${toString mgmtVlanId}" = {
                  matchConfig.Name = "${mgmtParent}.${toString mgmtVlanId}";
                  networkConfig = {
                    DHCP = "no";
                    LinkLocalAddressing = "no";
                    Bridge = "vlan${toString mgmtVlanId}";
                  };
                };
                "30-vlan${toString mgmtVlanId}" = {
                  matchConfig.Name = "vlan${toString mgmtVlanId}";
                  networkConfig = {
                    DHCP = "ipv4";
                    LinkLocalAddressing = "no";
                    IPv6AcceptRA = "no";
                  };
                };
              }
            else if mgmtManageDhcp && mgmtMode == "native" && mgmtParent != null then
              {

                "10-${mgmtParent}" = {
                  matchConfig.Name = mgmtParent;
                  networkConfig = {
                    DHCP = "ipv4";
                    LinkLocalAddressing = "no";
                    IPv6AcceptRA = "no";
                  };
                };
              }
            else
              { };

          mgmtNetdevs = if renderedHasMgmtVlan then { } else legacyMgmtNetdevs;

          mgmtNetworks = if renderedHasMgmtVlan || renderedHasNativeMgmt then { } else legacyMgmtNetworks;

          mgmtDhcpOverride =
            if renderedHasMgmtVlan && mgmtManageDhcp then
              {
                "30-vlan${toString mgmtVlanId}" =
                  let
                    existing = renderedNetworks."30-vlan${toString mgmtVlanId}" or { };
                  in
                  existing
                  // {
                    networkConfig = (existing.networkConfig or { }) // {
                      DHCP = "ipv4";
                      LinkLocalAddressing = "no";
                      IPv6AcceptRA = "no";
                    };
                  };
              }
            else
              { };

          hostRequiresNetworkd = requiresNetworkd {
            inherit
              renderedNetdevs
              renderedNetworks
              renderedContainers
              mgmtManageDhcp
              ;
          };

          publicIngressConfig = import ./s88/ControlModule/module/public-ingress.nix {
            lib = userLib;
            inherit pkgs hostName;
            controlPlane = effectiveCpm;
            runtimeFacts = rendererInput.runtimeFacts or { };
          };
          dnsValidationAuthorityConfig = import ./s88/ControlModule/module/dns-validation-authority.nix {
            lib = userLib;
            inherit pkgs hostName;
            controlPlane = effectiveCpm;
          };
        in
        {
          imports = [
            hostBuild.artifactModule
            publicIngressConfig
            dnsValidationAuthorityConfig
          ];

          networking.useNetworkd = lib.mkIf hostRequiresNetworkd true;
          systemd.network.enable = lib.mkIf hostRequiresNetworkd true;
          networking.useDHCP = lib.mkIf hostRequiresNetworkd false;
          networking.useHostResolvConf = userLib.mkForce false;

          systemd.network.netdevs = renderedNetdevs // mgmtNetdevs;
          systemd.network.networks = renderedNetworks // mgmtNetworks // mgmtDhcpOverride;
          containers = renderedContainers;

          systemd.services = builtins.listToAttrs (
            map (name: {
              name = "container@${name}";
              value = {
                after = [ "sops-nix.service" ];
              };
            }) (builtins.attrNames (rendered.containers or { }))
          );

          boot.kernel.sysctl."net.ipv4.ip_forward" = lib.mkDefault true;
        }
        // builtins.seq mgmtValidate { };

      canonicalRendererInput =
        {
          bundle,
          platformBinding ? null,
        }:
        network-realization-model.lib.validateRendererInput {
          inherit bundle platformBinding;
          expectedTarget = "nixos";
        };

      canonicalHostModule =
        {
          bundle,
          platformBinding ? null,
          ...
        }@rendererInput:
        let
          validated = canonicalRendererInput { inherit bundle platformBinding; };
          forwarded = builtins.removeAttrs rendererInput [
            "bundle"
            "platformBinding"
          ];
        in
        hostModule (
          forwarded
          // {
            cpm = validated.controlPlaneEnvelope;
            canonicalBundleIdentity = validated.bundleIdentity;
            canonicalBindingIdentity = validated.bindingIdentity;
          }
        );

      canonicalBuildHost =
        {
          bundle,
          platformBinding ? null,
          ...
        }@rendererInput:
        let
          validated = canonicalRendererInput { inherit bundle platformBinding; };
          forwarded = builtins.removeAttrs rendererInput [
            "bundle"
            "platformBinding"
          ];
          rendered = api.renderer.buildHostFromControlPlane (
            forwarded // { controlPlaneOut = validated.controlPlaneEnvelope; }
          );
        in
        rendered
        // {
          canonicalInput = {
            bundleIdentity = validated.bundleIdentity;
            bindingIdentity = validated.bindingIdentity;
            requestScope = validated.requestScope;
          };
        };

      mkVmApiForSystem =
        system:
        let
          buildVm =
            {
              cpm ? null,
              boxName,
              simulatedContainerDefaults ? { },
            }:
            let
              hostBuild = api.renderer.buildHostFromControlPlane {
                controlPlaneOut =
                  if cpm != null then
                    cpm
                  else
                    throw "network-renderer-nixos buildVm: 'cpm' (control plane model) is required.";
                selector = boxName;
                inherit system;
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
          capabilities.delegatedPrefixTenantRoutes = true;
          capabilities.publicIngressNatIntent = true;
          renderer =
            api.renderer
            // {
              inherit hostModule;
              canonical = {
                buildHost = canonicalBuildHost;
                hostModule = canonicalHostModule;
                validateInput = canonicalRendererInput;
              };
            }
            // vmApi;
        };
    in
    {
      lib = api // {
        renderer = api.renderer // {
          inherit hostModule;
          canonical = {
            buildHost = canonicalBuildHost;
            hostModule = canonicalHostModule;
            validateInput = canonicalRendererInput;
          };
        };
      };

      libBySystem = forAllSystems mkLibForSystem;

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

      checks = forAllSystems (
        system:
        let
          pkgs = import nixpkgs { inherit system; };
          bundle = network-realization-model.lib.realize {
            input = import "${network-realization-model}/examples/cpm-result.nix";
            requestScope = {
              kind = "complete-artifact";
              identity = "nixos-renderer-boundary";
            };
            rootLockIdentity = "network-renderer-nixos-flake-lock";
            producerRevision = network-realization-model.rev;
          };
          accepted = canonicalRendererInput { inherit bundle; };
          rawRejected =
            !(builtins.tryEval (
              builtins.deepSeq (canonicalRendererInput {
                bundle = {
                  control_plane_model = { };
                };
              }) true
            )).success;
        in
        assert accepted.bundleIdentity == bundle.bundleIdentity;
        assert accepted.controlPlaneEnvelope.control_plane_model == bundle.network.data;
        assert rawRejected;
        {
          canonical-renderer-input = pkgs.runCommand "network-renderer-nixos-canonical-input" { } ''
            touch "$out"
          '';
        }
      );
    };
}
