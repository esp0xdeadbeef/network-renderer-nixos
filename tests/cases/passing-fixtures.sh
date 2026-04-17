#!/usr/bin/env bash

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "${repo_root}/tests/lib/test-common.sh"

fixtures=(
  "passing/minimal-forwarding-model"
  "passing/minimal-forwarding-model-pppoe"
  "passing/hosted-runtime-targets"
  "passing/default-egress-reachability"
)

example_dir_for_fixture() {
  local rel="$1"
  local base
  base="$(basename "${rel}")"

  case "${base}" in
    minimal-forwarding-model)
      printf '%s\n' "${examples_root}/single-wan"
      ;;
    minimal-forwarding-model-pppoe)
      printf '%s\n' "${examples_root}/multi-wan"
      ;;
    hosted-runtime-targets)
      printf '%s\n' "${examples_root}/single-wan-with-nebula"
      ;;
    default-egress-reachability)
      printf '%s\n' "${examples_root}/single-wan-any-to-any-fw"
      ;;
    *)
      return 1
      ;;
  esac
}

resolve_case_dir_into() {
  local __outvar="$1"
  local rel="$2"
  local candidate

  candidate="$(example_dir_for_fixture "${rel}" || true)"
  if [[ -n "${candidate}" && -d "${candidate}" ]]; then
    printf -v "${__outvar}" '%s' "${candidate}"
    return 0
  fi

  resolve_fixture_dir_into "${__outvar}" "${rel}"
}

run_fixture() {
  local rel="$1"
  local fixture_dir
  local intent_path
  local inventory_path
  local tmp_dir
  local cpm_json

  resolve_case_dir_into fixture_dir "${rel}"

  intent_path="${fixture_dir}/input.nix"
  [[ -f "${intent_path}" ]] || intent_path="${fixture_dir}/intent.nix"

  inventory_path="${fixture_dir}/inventory.nix"

  [[ -f "${intent_path}" ]] || fail "FAIL fixture '${rel}' missing input.nix or intent.nix"
  [[ -f "${inventory_path}" ]] || fail "FAIL fixture '${rel}' missing inventory.nix"

  log "Running $(basename "${rel}")"

  tmp_dir="$(mktemp -d "${TMPDIR:-/tmp}/network-renderer-nixos-fixture.XXXXXX")"
  trap 'rm -rf "${tmp_dir}"' RETURN

  cpm_json="${tmp_dir}/control-plane-output.json"
  if ! build_control_plane_json "${intent_path}" "${inventory_path}" "${cpm_json}"; then
    echo "--- CONTROL PLANE OUTPUT ---"
    if [[ -f "${cpm_json}" ]]; then
      cat "${cpm_json}"
    fi
    fail "FAIL $(basename "${rel}"): artifact renderer evaluation failed"
  fi

  pass "$(basename "${rel}")"
  trap - RETURN
  rm -rf "${tmp_dir}"
}

for fixture in "${fixtures[@]}"; do
  run_fixture "${fixture}"
done
