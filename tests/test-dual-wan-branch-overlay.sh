#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
search_root="${repo_root}/../network-labs/examples"

source "${repo_root}/tests/lib/test-common.sh"

run_one() {
  local example_name="$1"
  local case_dir="${search_root}/${example_name}"
  local intent_path="${case_dir}/intent.nix"
  local inventory_path="${case_dir}/inventory-nixos.nix"

  [[ -f "${intent_path}" ]] || fail "missing intent.nix: ${intent_path}"
  [[ -f "${inventory_path}" ]] || fail "missing inventory-nixos.nix: ${inventory_path}"

  REPO_ROOT="${repo_root}" \
  INTENT_PATH="${intent_path}" \
  INVENTORY_PATH="${inventory_path}" \
  EXAMPLE_NAME="${example_name}" \
    nix eval \
      --extra-experimental-features 'nix-command flakes' \
      --impure --expr '
        let
          repoRoot = "path:" + builtins.getEnv "REPO_ROOT";
          intentPath = builtins.getEnv "INTENT_PATH";
          inventoryPath = builtins.getEnv "INVENTORY_PATH";
          exampleName = builtins.getEnv "EXAMPLE_NAME";
          flake = builtins.getFlake repoRoot;
          system = "x86_64-linux";
          hostBuild = flake.lib.renderer.buildHostFromPaths {
            selector = "lab-host";
            inherit system intentPath inventoryPath;
          };
          rendered = hostBuild.renderedHost;
          cpm = hostBuild.controlPlaneOut.control_plane_model;
          overlayA = cpm.data.enterpriseA."site-a".overlays."east-west";
          overlayB = cpm.data.enterpriseB."site-b".overlays."east-west";
          policyA = cpm.data.enterpriseA."site-a".runtimeTargets."enterpriseA-site-a-s-router-policy";
          policyB = cpm.data.enterpriseB."site-b".runtimeTargets."enterpriseB-site-b-b-router-policy";
          containerA = rendered.containers."s-router-core-isp-b";
          containerB = rendered.containers."b-router-core";
          bgpOk =
            if builtins.match ".*-bgp" exampleName != null then
              policyA.routingMode == "bgp"
              && builtins.isAttrs (policyA.bgp or null)
              && policyB.routingMode == "bgp"
              && builtins.isAttrs (policyB.bgp or null)
            else
              true;
        in
          builtins.isAttrs containerA
          && builtins.isAttrs containerB
          && overlayA.terminateOn == [ "s-router-core-isp-b" ]
          && overlayB.terminateOn == [ "b-router-core" ]
          && bgpOk
      ' >/dev/null

  pass "${example_name}"
}

run_one "dual-wan-branch-overlay"
run_one "dual-wan-branch-overlay-bgp"
