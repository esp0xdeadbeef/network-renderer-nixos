#!/usr/bin/env bash
# GAMP-ID: USR-MODEL-001-FS-001-HDS-002-SDS-001-001-SMS-001-CMC-001-015
# GAMP-SCOPE: software-integration-test
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${repo_root}/tests/lib/test-common.sh"

example_dir="$(flake_input_path network-labs)/examples/single-wan-uplink-static-egress"
intent_path="${example_dir}/intent.nix"
inventory_source="${example_dir}/inventory-nixos.nix"

tmp_dir="$(mktemp -d)"
result_json="$(mktemp)"
eval_stderr="$(mktemp)"
trap 'rm -rf "${tmp_dir}"; rm -f "${result_json}" "${eval_stderr}"' EXIT

inventory_path="${tmp_dir}/inventory.nix"
cat > "${inventory_path}" <<EOF
let
  base = import ${inventory_source};
  nodeName = "esp0xdeadbeef-site-a-s-router-access-client";
  node = base.realization.nodes.\${nodeName};
in
base // {
  realization = base.realization // {
    nodes = base.realization.nodes // {
      \${nodeName} = node // {
        advertisements = node.advertisements // {
          ipv6Ra = {
            tenant-client = node.advertisements.ipv6Ra.tenant-client // {
              managed = true;
              otherConfig = true;
              onLink = false;
              autonomous = false;
            };
          };
        };
      };
    };
  };
}
EOF

nix_eval_json_or_fail \
  access-slaac-pipeline-render \
  "${result_json}" \
  "${eval_stderr}" \
  env REPO_ROOT="${repo_root}" INTENT_PATH="${intent_path}" INVENTORY_PATH="${inventory_path}" \
    nix eval \
    --extra-experimental-features 'nix-command flakes' \
    --impure --json --expr '
      let
        repoRoot = "path:" + builtins.getEnv "REPO_ROOT";
        intentPath = builtins.getEnv "INTENT_PATH";
        inventoryPath = builtins.getEnv "INVENTORY_PATH";
        flake = builtins.getFlake repoRoot;
        system = builtins.currentSystem;
        hostBuild = import (builtins.getEnv "REPO_ROOT" + "/tests/nix/build-host-from-paths.nix") {
          selector = "lab-host";
          inherit system intentPath inventoryPath;
        };
        target =
          hostBuild.controlPlaneOut.control_plane_model.data.esp0xdeadbeef."site-a"
            .runtimeTargets."esp0xdeadbeef-site-a-s-router-access-client";
        cpmRa = builtins.head target.advertisements.ipv6Ra;
        container = hostBuild.renderedHost.containers.s-router-access-client;
        evaluated = flake.inputs.nixpkgs.lib.nixosSystem {
          inherit system;
          modules = [ container.config ];
        };
        services = evaluated.config.systemd.services;
        script = builtins.readFile services."radvd-generate-tenant-client".serviceConfig.ExecStart;
        checks = {
          cpm_preserves_managed_flag = cpmRa.managed == true;
          cpm_preserves_other_config_flag = cpmRa.otherConfig == true;
          cpm_preserves_on_link_flag = cpmRa.onLink == false;
          cpm_preserves_autonomous_flag = cpmRa.autonomous == false;
          renderer_emits_radvd_service = services ? "radvd-tenant-client";
          renderer_projects_managed_flag = builtins.match ".*AdvManagedFlag on;.*" script != null;
          renderer_projects_other_config_flag = builtins.match ".*AdvOtherConfigFlag on;.*" script != null;
          renderer_projects_on_link_flag = builtins.match ".*AdvOnLink off;.*" script != null;
          renderer_projects_autonomous_flag = builtins.match ".*AdvAutonomous off;.*" script != null;
        };
      in
      {
        ok = builtins.all (name: checks.${name}) (builtins.attrNames checks);
        failed = builtins.filter (name: !(checks.${name})) (builtins.attrNames checks);
        inherit checks;
      }
    '

assert_json_checks_ok access-slaac-pipeline-render "${result_json}"

echo "PASS access-slaac-pipeline-render"
