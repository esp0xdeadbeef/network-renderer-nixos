#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "${repo_root}/tests/lib/test-common.sh"

labs_root="$(flake_input_path network-labs)"
case_dir="${labs_root}/examples/single-wan-vlan-trunk-lanes"

intent_path="${case_dir}/intent.nix"
inventory_path="${case_dir}/inventory.nix"

if [[ ! -f "$intent_path" ]]; then
  fail "missing intent.nix: ${intent_path}"
fi
if [[ ! -f "$inventory_path" ]]; then
  fail "missing inventory.nix: ${inventory_path}"
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

  # Expect VLAN netdevs synthesized on the host trunk bridge, without booting a VM.
  _jq -e '
    .hosts["lab-host"].network.netdevs
    | to_entries
    | map(.value.netdevConfig.Name)
    | (index("br-trunk.100") != null and index("br-trunk.200") != null)
  ' ./90-render.json >/dev/null
)

pass "vlan-trunk-lanes"
