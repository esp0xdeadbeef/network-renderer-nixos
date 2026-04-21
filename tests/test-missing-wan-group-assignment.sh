#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
search_root="${repo_root}/../network-labs/examples"

source "${repo_root}/tests/lib/test-common.sh"

case_dir="${search_root}/dual-wan-branch-overlay"
intent_path="${case_dir}/intent.nix"
inventory_path="${case_dir}/inventory.nix"

[[ -f "${intent_path}" ]] || fail "missing intent.nix: ${intent_path}"
[[ -f "${inventory_path}" ]] || fail "missing inventory.nix: ${inventory_path}"

tmp_dir="$(mktemp -d "${TMPDIR:-/tmp}/network-renderer-nixos-missing-wan-map.XXXXXX")"
trap 'rm -rf "${tmp_dir}"' EXIT

(
  cd "${tmp_dir}"
  build_cpm_json "${intent_path}" "${inventory_path}" "${tmp_dir}/cpm.json"

  set +e
  nix run \
    --no-write-lock-file \
    --extra-experimental-features 'nix-command flakes' \
    "${repo_root}"#render-dry-config \
    -- \
    --debug \
    "${tmp_dir}/cpm.json" \
    >/dev/null \
    2>"${tmp_dir}/render.stderr"
  rc=$?
  set -e

  [[ "${rc}" -ne 0 ]] || fail "expected missing WAN assignment render failure"
  grep -F "strict rendering requires explicit WAN uplink assignment for host 'lab-host'" "${tmp_dir}/render.stderr" >/dev/null \
    || fail "missing strict WAN assignment failure"
  grep -F '"enterpriseB::site-b::b-router-core"' "${tmp_dir}/render.stderr" >/dev/null \
    || fail "missing expected WAN group name in failure output"
)

pass "missing-wan-group-assignment"
