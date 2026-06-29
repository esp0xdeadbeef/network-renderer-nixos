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
          netdevs = nixosEvaluated.config.systemd.network.netdevs or { };
          networks = nixosEvaluated.config.systemd.network.networks or { };
          eth0Vlans = networks."20-eth0".networkConfig.VLAN or [ ];
          controlPlane = builtins.fromJSON clientsEvaluated.config.environment.etc."network-artifacts/control-plane.json".text;
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
      '

echo "PASS FS-380 active-lab multi-uplink WAN attachment"
