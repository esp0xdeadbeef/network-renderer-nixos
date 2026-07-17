#!/usr/bin/env bash
# GAMP-ID: FS-540-HDS-010-SDS-010-SMS-020
# GAMP-SCOPE: software-module-test
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${repo_root}/tests/lib/test-common.sh"
source "${repo_root}/tests/lib/adjacent-repo-paths.sh"

labs_repo="$(resolve_adjacent_repo NETWORK_LABS_PATH network-labs)"
tmp_dir="$(mktemp -d "${TMPDIR:-/tmp}/network-renderer-nixos-fs540-sms020.XXXXXX")"
trap 'rm -rf "${tmp_dir}"' EXIT
ln -s "${labs_repo}/GAMP" "${tmp_dir}/GAMP"
current_lab_dir="${tmp_dir}/current-lab"
NETWORK_LABS_CURRENT_LAB_DIR="${current_lab_dir}" \
  bash "${labs_repo}/scripts/select-current-lab.sh" SIT FS-540-HDS-010-SDS-010 >/dev/null

if [[ ! -f "${current_lab_dir}/metadata.nix" ]]; then
  echo "FAIL FS-540 hostModule uplink shadow regression: missing selected network-labs current-lab at ${current_lab_dir}" >&2
  exit 1
fi

nix_eval_true_or_fail "FS-540 hostModule uplink parent network is not shadowed" \
  env REPO_ROOT="${repo_root}" CURRENT_LAB_DIR="${current_lab_dir}" \
    nix eval \
      --extra-experimental-features 'nix-command flakes' \
      --impure --expr '
        let
          repoRoot = builtins.getEnv "REPO_ROOT";
          flake = builtins.getFlake ("path:" + repoRoot);
          lib = flake.inputs.nixpkgs.lib;
          system = "x86_64-linux";
          currentLabDir = builtins.getEnv "CURRENT_LAB_DIR";
          metadata = import (currentLabDir + "/metadata.nix");
          cpmOut = flake.inputs.network-control-plane-model.lib.${system}.compileAndBuildFromPaths {
            inputPath = currentLabDir + "/intent.nix";
            inventoryPath = currentLabDir + "/inventory-nixos.nix";
            validateForwardingModel = false;
            validateRuntimeModel = false;
          };
          module = flake.lib.renderer.hostModule {
            inherit lib system;
            hostName = "s-router-nixos";
            cpm = cpmOut;
            selectorFile = "tests/test-fs540-hds010-sds010-sms020-hostmodule-uplink-no-shadow.sh";
          };
          evaluated = lib.nixosSystem {
            inherit system;
            modules = [ module ];
          };
          netdevs = evaluated.config.systemd.network.netdevs or { };
          networks = evaluated.config.systemd.network.networks or { };
          eth0Vlans = networks."20-eth0".networkConfig.VLAN or [ ];
          require = cond: msg: if cond then true else throw msg;
        in
          require (metadata.layer == "SIT" && metadata.selector == "FS-540-HDS-010-SDS-010")
            "network-labs current-lab must be selected to SIT FS-540-HDS-010-SDS-010 for this active-lab regression"
          && require (builtins.hasAttr "11-eth0.4" netdevs)
            "hostModule must emit the testnet VLAN4 netdev from CPM deploymentHosts"
          && require (builtins.hasAttr "21-eth0.4" networks)
            "hostModule must emit the testnet VLAN4 bridge attachment from CPM deploymentHosts"
          && require (builtins.hasAttr "20-eth0" networks)
            "hostModule must emit the CPM-derived parent eth0 network"
          && require (builtins.elem "eth0.2" eth0Vlans && builtins.elem "eth0.4" eth0Vlans)
            "CPM-derived parent eth0 network must include both management VLAN2 and testnet VLAN4"
          && require (!(builtins.hasAttr "10-eth0" networks))
            "legacy management shim must not emit 10-eth0.network that shadows the CPM-derived 20-eth0.network"
          && require (!(builtins.hasAttr "10-eth0.2" netdevs))
            "legacy management shim must not emit duplicate lower-priority management VLAN netdev"
      '

echo "PASS FS-540 hostModule uplink parent network is not shadowed"
