#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${repo_root}/tests/lib/test-common.sh"
source "${repo_root}/tests/lib/example-render-scan.sh"

result_json="$(mktemp)"
eval_stderr="$(mktemp)"
trap 'rm -f "${result_json}" "${eval_stderr}"' EXIT

labs_root="$(flake_input_path network-labs)"
violations="$(mktemp)"
trap 'rm -f "${result_json}" "${eval_stderr}" "${violations}"' EXIT

check_box() {
  local label="$1"
  local box_name="$2"
  local intent_path="$3"
  local inventory_path="$4"
  local cpm_path
  cpm_path="$(mktemp)"

  build_cpm_json "${intent_path}" "${inventory_path}" "${cpm_path}"

  nix_eval_json_or_fail \
    "policy-forward-default-paths:${label}:${box_name}" \
    "${result_json}" \
    "${eval_stderr}" \
    env REPO_ROOT="${repo_root}" \
      BOX_NAME="${box_name}" \
      INTENT_PATH="${intent_path}" \
      INVENTORY_PATH="${inventory_path}" \
      CPM_PATH="${cpm_path}" \
      nix eval \
      --extra-experimental-features 'nix-command flakes' \
      --impure --json \
      --file "${repo_root}/tests/nix/policy-forward-default-paths.nix"

  if [[ "$(_jq -r '(.missingDefaultRoutes // []) | length' "${result_json}")" != "0" ]]; then
    {
      echo "!!!! ${label}:${box_name}: policy forwarding default path is not production-safe"
      _jq -S '{missingDefaultRoutes}' "${result_json}"
    } >>"${violations}"
  fi

  rm -f "${cpm_path}"
}

check_example() {
  local example_dir="$1"
  local tmp_dir="$2"
  local dry_json="${tmp_dir}/dry.json"

  render_example_dry_json "${example_dir}" "${tmp_dir}" "${dry_json}"
  while IFS= read -r box_name; do
    check_box \
      "$(basename "${example_dir}")" \
      "${box_name}" \
      "${example_dir}/intent.nix" \
      "${example_dir}/inventory-nixos.nix"
  done < <(_jq -r '.render.containers | keys[]' "${dry_json}")
}

for example_dir in \
  "${labs_root}/examples/single-wan" \
  "${labs_root}/examples/single-wan-with-nebula" \
  "${labs_root}/examples/overlay-east-west" \
  "${labs_root}/examples/s-router-overlay-dns-lane-policy"
do
  tmp_dir="$(mktemp -d "${TMPDIR:-/tmp}/network-renderer-nixos-policy-paths.XXXXXX")"
  check_example "${example_dir}" "${tmp_dir}"
  rm -rf "${tmp_dir}"
done

if [[ -s "${violations}" ]]; then
  cat "${violations}" >&2
  fail "!!!! policy-forward-default-paths: downstream-uplink nft allows must have matching default routes"
fi

pass "policy-forward-default-paths"
