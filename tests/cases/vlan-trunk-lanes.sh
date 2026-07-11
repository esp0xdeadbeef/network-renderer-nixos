#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "${repo_root}/tests/lib/test-common.sh"

case_dir="${repo_root}/tests/fixtures/s-router-overlay-dns-lane-policy"

intent_path="${case_dir}/intent.nix"
inventory_path="${case_dir}/inventory-nixos.nix"

if [[ ! -f "$intent_path" ]]; then
  fail "missing intent.nix: ${intent_path}"
fi
if [[ ! -f "$inventory_path" ]]; then
  fail "missing inventory-nixos.nix: ${inventory_path}"
fi

tmp_dir="$(mktemp -d "${TMPDIR:-/tmp}/network-renderer-nixos-vlan-trunk.XXXXXX")"
trap 'rm -rf "${tmp_dir}"' EXIT

(
  cd "${tmp_dir}"

  build_cpm_json "${intent_path}" "${inventory_path}" "${tmp_dir}/cpm.json"

  nix run \
    --no-write-lock-file \
    --extra-experimental-features 'nix-command flakes' \
    "${repo_root}"#render-dry-config \
    -- \
    --debug \
    "${tmp_dir}/cpm.json" \
    >/dev/null

  # Expect VLAN netdevs synthesized from the host trunk inventory, without booting a VM.
  _jq -e '
    .hosts["s-router-test"].network.netdevs
    | to_entries
    | map(.value.netdevConfig.Name)
    | (
      index("eth0.301") != null
      and index("eth0.305") != null
      and index("eth0.306") != null
    )
  ' ./90-render.json >/dev/null
)

pass "vlan-trunk-lanes"
