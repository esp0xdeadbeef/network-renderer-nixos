#!/usr/bin/env bash
# GAMP-ID: USR-MODEL-001-FS-001-HDS-002-SDS-001-001-SMS-001-CMC-001-012
# GAMP-SCOPE: software-integration-test
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${repo_root}/tests/lib/test-common.sh"

example_dir="$(flake_input_path network-labs)/examples/single-wan"
intent_path="${example_dir}/intent.nix"
inventory_source="${example_dir}/inventory-nixos.nix"

tmp_dir="$(mktemp -d)"
result_json="${tmp_dir}/result.json"
eval_stderr="${tmp_dir}/eval.stderr"
trap 'rm -rf "${tmp_dir}"' EXIT

cp "${inventory_source}" "${tmp_dir}/base.nix"
inventory_path="${tmp_dir}/inventory.nix"
cat >"${inventory_path}" <<'EOF'
let
  base = import ./base.nix;
  nodeName = "esp0xdeadbeef-site-a-s-router-access-client";
  node = base.realization.nodes.${nodeName};
in
base // {
  realization = base.realization // {
    nodes = base.realization.nodes // {
      ${nodeName} = node // {
        advertisements = (node.advertisements or { }) // {
          dhcp4 = {
            tenant-client = {
              id = "client";
              subnet = "10.20.20.0/24";
              pool = {
                start = "10.20.20.100";
                end = "10.20.20.199";
              };
              serverAddress = "router-self";
              router = "10.20.20.1";
              dnsServers = [ "router-self" ];
              domain = "lan.";
            };
          };
        };
        statePolicy = (node.statePolicy or { }) // {
          persistence = ((node.statePolicy or { }).persistence or { }) // {
            required = true;
            root = "/persist/network/state";
          };
        };
      };
    };
  };
}
EOF

nix_eval_json_or_fail \
  access-dhcp4-pipeline-render \
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
        cpmDhcp4 = builtins.head target.advertisements.dhcp4;
        cpmLease = builtins.head target.stateContracts.persistence.dhcp4Leases;
        container = hostBuild.renderedHost.containers.s-router-access-client;
        evaluated = flake.inputs.nixpkgs.lib.nixosSystem {
          inherit system;
          modules = [ container.config ];
        };
        services = evaluated.config.systemd.services;
        checks = {
          cpm_has_explicit_dhcp4 = cpmDhcp4.interface == "tenant-client";
          cpm_preserves_subnet = cpmDhcp4.subnet == "10.20.20.0/24";
          cpm_preserves_pool =
            (cpmDhcp4.pool.start or null) == "10.20.20.100"
            && (cpmDhcp4.pool.end or null) == "10.20.20.199";
          cpm_preserves_router = cpmDhcp4.router == "10.20.20.1";
          cpm_preserves_lease_state =
            cpmLease.path == "/persist/network/state/dhcp4/esp0xdeadbeef-site-a-s-router-access-client/client";
          renderer_emits_generator = services ? "gen-kea-client";
          renderer_emits_service = services ? "kea-dhcp4-client";
          renderer_uses_kea_dhcp4 =
            builtins.match ".*kea-dhcp4.*"
              (builtins.toString services."kea-dhcp4-client".serviceConfig.ExecStart) != null;
          renderer_wires_generator =
            builtins.elem "gen-kea-client.service" services."kea-dhcp4-client".requires;
        };
      in
      {
        ok = builtins.all (name: checks.${name}) (builtins.attrNames checks);
        failed = builtins.filter (name: !(checks.${name})) (builtins.attrNames checks);
        inherit checks;
      }
    '

assert_json_checks_ok access-dhcp4-pipeline-render "${result_json}"

echo "PASS access-dhcp4-pipeline-render"
