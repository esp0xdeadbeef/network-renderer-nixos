#!/usr/bin/env bash
# GAMP-ID: USR-MODEL-001-FS-001-HDS-002-SDS-001-001-SMS-001-CMC-001-014
# GAMP-SCOPE: software-integration-test
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${repo_root}/tests/lib/test-common.sh"

example_dir="$(flake_input_path network-labs)/examples/single-wan"
intent_path="${example_dir}/intent.nix"
inventory_path="${example_dir}/inventory-nixos.nix"

result_json="$(mktemp)"
eval_stderr="$(mktemp)"
trap 'rm -f "${result_json}" "${eval_stderr}"' EXIT

nix_eval_json_or_fail \
  access-radvd-pipeline-render \
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
        checks = {
          cpm_has_explicit_ra = cpmRa.interface == "tenant-client";
          cpm_preserves_ra_prefix = cpmRa.prefixes == [ "fd42:dead:beef:20::/64" ];
          cpm_preserves_ra_rdnss = cpmRa.rdnss == [ "fd42:dead:beef:20:0:0:0:1" ];
          renderer_emits_generator = services ? "radvd-generate-tenant-client";
          renderer_emits_service = services ? "radvd-tenant-client";
          renderer_uses_radvd =
            builtins.match ".*radvd.*"
              (builtins.toString services."radvd-tenant-client".serviceConfig.ExecStart) != null;
          renderer_wires_generator =
            builtins.elem "radvd-generate-tenant-client.service" services."radvd-tenant-client".requires;
        };
      in
      {
        ok = builtins.all (name: checks.${name}) (builtins.attrNames checks);
        failed = builtins.filter (name: !(checks.${name})) (builtins.attrNames checks);
        inherit checks;
      }
    '

assert_json_checks_ok access-radvd-pipeline-render "${result_json}"

echo "PASS access-radvd-pipeline-render"
