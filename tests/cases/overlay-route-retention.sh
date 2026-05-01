#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "${repo_root}/tests/lib/test-common.sh"

example_dir="$(flake_input_path network-labs)/examples/dual-wan-branch-overlay"
intent_path="${example_dir}/intent.nix"
inventory_path="${example_dir}/inventory-nixos.nix"

[[ -f "${intent_path}" ]] || fail "missing intent: ${intent_path}"
[[ -f "${inventory_path}" ]] || fail "missing inventory: ${inventory_path}"

tmp_dir="$(mktemp -d "${TMPDIR:-/tmp}/network-renderer-nixos-overlay-routes.XXXXXX")"
trap 'rm -rf "${tmp_dir}"' EXIT

(
  cd "${tmp_dir}"
  build_cpm_json "${intent_path}" "${inventory_path}" "${tmp_dir}/cpm.json"

  REPO_ROOT="${repo_root}" \
  CPM_PATH="${tmp_dir}/cpm.json" \
  INVENTORY_PATH="${inventory_path}" \
    nix eval \
    --extra-experimental-features 'nix-command flakes' \
    --impure --json \
    --expr '
      let
        repoRoot = "path:" + builtins.getEnv "REPO_ROOT";
        cpmPath = builtins.getEnv "CPM_PATH";
        inventoryPath = builtins.getEnv "INVENTORY_PATH";
        flake = builtins.getFlake repoRoot;
      in
      flake.lib.renderer.renderDryConfig {
        inherit cpmPath inventoryPath;
        exampleDir = builtins.dirOf cpmPath;
        debug = true;
      }
    ' \
    > ./90-dry-config.json

  _jq -e '
    .render.nodes["enterpriseA::site-a::enterpriseA-site-a-s-router-core-nebula"].interfaces["overlay-east-west"].routes
    | map(.dst)
    | index("10.60.10.0/24") != null
  ' ./90-dry-config.json >/dev/null

  _jq -e '
    .render.nodes["enterpriseA::site-a::enterpriseA-site-a-s-router-core-nebula"].interfaces["overlay-east-west"].routes
    | map(.dst)
    | index("fd42:dead:feed:10::/64") != null
  ' ./90-dry-config.json >/dev/null

  _jq -e '
    .render.nodes["enterpriseB::site-b::enterpriseB-site-b-b-router-core-nebula"].interfaces["overlay-east-west"].routes
    | map(.dst)
    | index("10.20.20.0/24") != null
  ' ./90-dry-config.json >/dev/null

  _jq -e '
    .render.nodes["enterpriseB::site-b::enterpriseB-site-b-b-router-core-nebula"].interfaces["overlay-east-west"].routes
    | map(.dst)
    | index("fd42:dead:beef:20::/64") != null
  ' ./90-dry-config.json >/dev/null

  _jq -e '
    .render.nodes["enterpriseA::site-a::enterpriseA-site-a-s-router-core-nebula"].interfaces["overlay-east-west"].renderedHostBridgeName
    ==
    .render.nodes["enterpriseB::site-b::enterpriseB-site-b-b-router-core-nebula"].interfaces["overlay-east-west"].renderedHostBridgeName
  ' ./90-dry-config.json >/dev/null
)

pass "overlay route retention"
