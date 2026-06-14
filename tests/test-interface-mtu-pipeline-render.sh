#!/usr/bin/env bash
# GAMP-ID: USR-MODEL-001-FS-001-HDS-002-SDS-001-001-SMS-001-CMC-001-005
# GAMP-SCOPE: software-integration-test
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${repo_root}/tests/lib/test-common.sh"

example_dir="$(flake_input_path network-labs)/examples/single-wan-uplink-static-egress"
intent_path="${example_dir}/intent.nix"
inventory_source="${example_dir}/inventory-nixos.nix"

tmp_dir="$(mktemp -d)"
result_json="${tmp_dir}/result.json"
eval_stderr="${tmp_dir}/eval.stderr"
trap 'rm -rf "${tmp_dir}"' EXIT

cp "${inventory_source}" "${tmp_dir}/inventory.nix"
chmod u+w "${tmp_dir}/inventory.nix"

perl -0pi -e 's/interface = \{ name = "ens4"; addr4 = "192\.0\.2\.2\/24"; \}; uplink = "wan";/interface = { name = "ens4"; addr4 = "192.0.2.2\/24"; mtu = 1492; }; uplink = "wan";/' "${tmp_dir}/inventory.nix"
rg -q 'mtu = 1492' "${tmp_dir}/inventory.nix" \
  || fail "interface-mtu-pipeline-render: failed to inject explicit MTU into inventory fixture"

nix_eval_json_or_fail \
  interface-mtu-pipeline-render \
  "${result_json}" \
  "${eval_stderr}" \
  env REPO_ROOT="${repo_root}" INTENT_PATH="${intent_path}" INVENTORY_PATH="${tmp_dir}/inventory.nix" \
    nix eval \
    --extra-experimental-features 'nix-command flakes' \
    --impure --json --expr '
      let
        repoPath = builtins.getEnv "REPO_ROOT";
        repoRoot = "path:" + repoPath;
        intentPath = builtins.getEnv "INTENT_PATH";
        inventoryPath = builtins.getEnv "INVENTORY_PATH";
        flake = builtins.getFlake repoRoot;
        lib = flake.inputs.nixpkgs.lib;
        system = builtins.currentSystem;
        hostBuild = import (builtins.getEnv "REPO_ROOT" + "/tests/nix/build-host-from-paths.nix") {
          selector = "lab-host";
          inherit system intentPath inventoryPath;
        };
        target =
          hostBuild.controlPlaneOut.control_plane_model.data.esp0xdeadbeef."site-a"
            .runtimeTargets."esp0xdeadbeef-site-a-s-router-core-wan";
        cpmIface = target.effectiveRuntimeRealization.interfaces.wan;
        hostPlan = import (repoPath + "/s88/Unit/render/host-plan.nix") {
          inherit
            lib
            repoPath
            ;
          hostName = "lab-host";
          cpm = hostBuild.controlPlaneOut;
          inventory = hostBuild.globalInventory;
          hostContext = hostBuild.hostContext;
        };
        debugContainers = import (repoPath + "/s88/ControlModule/render/containers.nix") {
          inherit
            lib
            repoPath
            hostPlan
            ;
          cpm = hostBuild.controlPlaneOut;
          inventory = hostBuild.globalInventory;
          debugEnabled = true;
        };
        debugModel = debugContainers.s-router-core-wan.specialArgs.s88Debug;
        projectedIfName = debugModel.interfaces.wan.containerInterfaceName;
        container = hostBuild.renderedHost.containers.s-router-core-wan;
        evaluated = flake.inputs.nixpkgs.lib.nixosSystem {
          inherit system;
          modules = [ container.config ];
        };
        networks = evaluated.config.systemd.network.networks;
        runtimeNetwork = networks."10-${projectedIfName}";
        checks = {
          cpm_preserves_mtu = cpmIface.mtu == 1492;
          renderer_model_preserves_mtu = debugModel.interfaces.wan.mtu == 1492;
          renderer_projects_mtu = ((runtimeNetwork.linkConfig or { }).MTUBytes or null) == 1492;
          renderer_preserves_interface_name = ((runtimeNetwork.matchConfig or { }).Name or null) == projectedIfName;
        };
      in
      {
        ok = builtins.all (name: checks.${name}) (builtins.attrNames checks);
        failed = builtins.filter (name: !(checks.${name})) (builtins.attrNames checks);
        inherit checks;
      }
    '

assert_json_checks_ok interface-mtu-pipeline-render "${result_json}"

echo "PASS interface-mtu-pipeline-render"
