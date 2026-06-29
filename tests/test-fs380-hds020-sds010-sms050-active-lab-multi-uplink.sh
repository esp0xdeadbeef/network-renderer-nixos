#!/usr/bin/env bash
# GAMP-ID: FS-380-HDS-020-SDS-010-SMS-050
# GAMP-SCOPE: software-module-test
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${repo_root}/tests/lib/test-common.sh"

labs_repo="${NETWORK_LABS_PATH:-${repo_root}/../network-labs}"

if [[ ! -f "${labs_repo}/current-lab/metadata.nix" ]]; then
  echo "FAIL FS-380 active-lab multi-uplink regression: missing network-labs current-lab at ${labs_repo}" >&2
  exit 1
fi

nix_eval_true_or_fail "FS-380 active-lab multi-uplink WAN attachment" \
  env REPO_ROOT="${repo_root}" NETWORK_LABS_PATH="${labs_repo}" \
    nix eval \
      --extra-experimental-features 'nix-command flakes' \
      --impure --expr '
        let
          repoRoot = builtins.getEnv "REPO_ROOT";
          labsRepo = builtins.getEnv "NETWORK_LABS_PATH";
          flake = builtins.getFlake ("path:" + repoRoot);
          lib = flake.inputs.nixpkgs.lib;
          system = "x86_64-linux";
          metadata = import (labsRepo + "/current-lab/metadata.nix");
          cpmNixosOut = flake.inputs.network-control-plane-model.lib.${system}.compileAndBuildFromPaths {
            inputPath = labsRepo + "/current-lab/intent-s-router-nixos.nix";
            inventoryPath = labsRepo + "/current-lab/inventory-s-router-nixos.nix";
            validateForwardingModel = false;
            validateRuntimeModel = false;
          };
          cpmClientsOut = flake.inputs.network-control-plane-model.lib.${system}.compileAndBuildFromPaths {
            inputPath = labsRepo + "/current-lab/intent-s-router-test-clients.nix";
            inventoryPath = labsRepo + "/current-lab/inventory-s-router-test-clients.nix";
            validateForwardingModel = false;
            validateRuntimeModel = false;
          };
          nixosModule = flake.lib.renderer.hostModule {
            inherit lib system;
            hostName = "s-router-nixos";
            cpm = cpmNixosOut;
            selectorFile = "tests/test-fs380-hds020-sds010-sms050-active-lab-multi-uplink.sh";
          };
          clientsModule = flake.lib.renderer.hostModule {
            inherit lib system;
            hostName = "s-router-test-clients";
            cpm = cpmClientsOut;
            selectorFile = "tests/test-fs380-hds020-sds010-sms050-active-lab-multi-uplink.sh";
          };
          nixosEvaluated = lib.nixosSystem {
            inherit system;
            modules = [ nixosModule ];
          };
          clientsEvaluated = lib.nixosSystem {
            inherit system;
            modules = [ clientsModule ];
          };
          downstreamSelectorNetworks =
            nixosEvaluated.config.containers.downstream-selector.config.systemd.network.networks;
          downstreamP1 = downstreamSelectorNetworks."10-p1" or { };
          downstreamP1Routes = downstreamP1.routes or [ ];
          downstreamP1Rules = downstreamP1.routingPolicyRules or [ ];
          downstreamInternetDefaultRoute = lib.findFirst
            (
              route:
                (route.Destination or null) == "0.0.0.0/0"
                && (route.Gateway or null) == "10.10.0.3"
                && builtins.isInt (route.Table or null)
            )
            null
            downstreamP1Routes;
          downstreamInternetTable =
            if downstreamInternetDefaultRoute == null
            then null
            else downstreamInternetDefaultRoute.Table;
          downstreamClientIngressRules = lib.filter
            (
              rule:
                (rule.Family or null) == "ipv4"
                && (rule.IncomingInterface or null) == "p0"
                && (rule.From or null) == "10.20.20.0/24"
            )
            downstreamP1Rules;
          downstreamClientIngressUsesInternetTable =
            builtins.any (rule: (rule.Table or null) == downstreamInternetTable) downstreamClientIngressRules;
          downstreamClientIngressUsesWrongTable =
            builtins.any
              (
                rule:
                  builtins.isInt (rule.Table or null)
                  && (rule.Table or null) != downstreamInternetTable
                  && (rule.Table or null) != 254
              )
              downstreamClientIngressRules;
          netdevs = nixosEvaluated.config.systemd.network.netdevs or { };
          networks = nixosEvaluated.config.systemd.network.networks or { };
          eth0Vlans = networks."20-eth0".networkConfig.VLAN or [ ];
          clientHostContainers = builtins.attrNames (clientsEvaluated.config.containers or { });
          controlPlane = builtins.fromJSON clientsEvaluated.config.environment.etc."network-artifacts/control-plane.json".text;
          renderedClientHost = builtins.fromJSON clientsEvaluated.config.environment.etc."network-artifacts/rendered-host.json".text;
          testClientsHost = controlPlane.deploymentHosts."s-router-test-clients" or { };
          require = cond: msg: if cond then true else throw msg;
        in
          require (metadata.layer == "SIT" && metadata.selector == "FS-380-HDS-020-SDS-010")
            "network-labs current-lab must be selected to SIT FS-380-HDS-020-SDS-010"
          && require (builtins.hasAttr "11-eth0.4" netdevs)
            "s-router-nixos must emit VLAN4 netdev for the first explicit internet uplink"
          && require (builtins.hasAttr "11-eth0.5" netdevs)
            "s-router-nixos must emit VLAN5 netdev for the second explicit internet uplink"
          && require (builtins.elem "eth0.4" eth0Vlans && builtins.elem "eth0.5" eth0Vlans)
            "s-router-nixos parent eth0 must retain both internet VLAN children"
          && require ((testClientsHost.accessHandoff.kind or null) == "pppoe")
            "s-router-test-clients artifact must preserve deploymentHosts.s-router-test-clients.accessHandoff.kind"
          && require ((testClientsHost.accessHandoff.server or null) == "emulated-isp")
            "s-router-test-clients artifact must preserve deploymentHosts.s-router-test-clients.accessHandoff.server"
          && require (clientHostContainers == [ ])
            "s-router-test-clients must not render router fabric containers"
          && require (renderedClientHost.selectedUnits == [ ])
            "s-router-test-clients rendered artifact must preserve empty router unit selection"
          && require (downstreamInternetTable != null)
            "downstream-selector p1 must emit the explicit internet default route in a policy table"
          && require downstreamClientIngressUsesInternetTable
            "downstream-selector traffic entering from client-edge on p0 must select the same table that contains the p1 internet default route"
          && require (!downstreamClientIngressUsesWrongTable)
            "downstream-selector must not send client-edge ingress traffic to a different non-main table than the p1 internet default route"
      '

echo "PASS FS-380 active-lab multi-uplink WAN attachment"
