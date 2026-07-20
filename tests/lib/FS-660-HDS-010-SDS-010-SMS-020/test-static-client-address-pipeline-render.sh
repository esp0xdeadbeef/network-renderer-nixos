#!/usr/bin/env bash
# GAMP-SCOPE: software-integration-test
# GAMP-ID: FS-660-HDS-010-SDS-010-SMS-020
set -euo pipefail

repo_root="${SMS_TEST_REPO_ROOT:-$(git -C "$(dirname "${BASH_SOURCE[0]}")" rev-parse --show-toplevel)}"
source "${repo_root}/tests/lib/test-common.sh"

example_dir="$(flake_input_path network-labs)/examples/single-wan"
intent_path="${example_dir}/intent.nix"
inventory_path="${example_dir}/inventory-nixos.nix"

result_json="$(mktemp)"
eval_stderr="$(mktemp)"
trap 'rm -f "${result_json}" "${eval_stderr}"' EXIT

nix_eval_json_or_fail \
  static-client-address-pipeline-render \
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
        cpmIface = target.effectiveRuntimeRealization.interfaces.tenant-client;
        container = hostBuild.renderedHost.containers.s-router-access-client;
        evaluated = flake.inputs.nixpkgs.lib.nixosSystem {
          inherit system;
          modules = [ container.config ];
        };
        network = evaluated.config.systemd.network.networks."10-tenant-client";
        checks = {
          cpm_carries_static_ipv4 = cpmIface.addr4 == "10.20.20.1/24";
          cpm_carries_static_ipv6 = cpmIface.addr6 == "fd42:dead:beef:20:0:0:0:1/64";
          renderer_projects_static_ipv4 =
            builtins.elem "10.20.20.1/24" (network.address or [ ]);
          renderer_projects_static_ipv6 =
            builtins.elem "fd42:dead:beef:20:0:0:0:1/64" (network.address or [ ]);
          renderer_does_not_enable_dynamic_dhcp = !((network.networkConfig or { }) ? DHCP);
        };
      in
      {
        ok = builtins.all (name: checks.${name}) (builtins.attrNames checks);
        failed = builtins.filter (name: !(checks.${name})) (builtins.attrNames checks);
        inherit checks;
      }
    '

assert_json_checks_ok static-client-address-pipeline-render "${result_json}"

echo "PASS static-client-address-pipeline-render"
