#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "${repo_root}/tests/lib/test-common.sh"

labs_root="$(flake_input_path network-labs)"
example_dir="${labs_root}/examples/dual-wan-branch-overlay"
intent_nix="${example_dir}/intent.nix"
inventory_nix="${example_dir}/inventory-nixos.nix"

if [[ ! -f "${intent_nix}" || ! -f "${inventory_nix}" ]]; then
  fail "missing dual-wan-branch-overlay example inputs in network-labs flake input"
fi

tmp_dir="$(mktemp -d "${TMPDIR:-/tmp}/network-renderer-nixos-host-veth.XXXXXX")"
trap 'rm -rf "${tmp_dir}"' EXIT

log "Rendering dual-wan-branch-overlay for host-veth sufficiency checks"
(
  cd "${tmp_dir}"
  build_cpm_json "${intent_nix}" "${inventory_nix}" "${tmp_dir}/cpm.json"

  nix run \
    --no-write-lock-file \
    --extra-experimental-features 'nix-command flakes' \
    "${repo_root}"#render-dry-config \
    -- \
    --debug \
    "${tmp_dir}/cpm.json" \
    >/dev/null
)

render_json="${tmp_dir}/90-render.json"
dry_json="${tmp_dir}/90-dry-config.json"

python3 "${repo_root}/tests/helpers/check-host-veth-consumer-sufficiency.py" \
  "${render_json}" \
  "${dry_json}"

pass "host-veth consumer sufficiency"
