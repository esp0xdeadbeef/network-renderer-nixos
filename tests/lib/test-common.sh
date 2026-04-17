#!/usr/bin/env bash

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
system="${NIX_SYSTEM:-$(nix eval --impure --raw --expr 'builtins.currentSystem')}"
examples_root="${repo_root}/../network-labs/examples"
nix_test_dir="${repo_root}/tests/nix"

log() {
  echo "==> $*"
}

pass() {
  echo "PASS $1"
}

fail() {
  echo "$1" >&2
  exit 1
}

_fixture_roots() {
  printf '%s\n' \
    "${repo_root}/tests/fixtures" \
    "${repo_root}/fixtures" \
    "${repo_root}/../network-control-plane-model/tests/fixtures" \
    "${repo_root}/../network-control-plane-model/fixtures" \
    "${repo_root}/../network-forwarding-model/tests/fixtures" \
    "${repo_root}/../network-forwarding-model/fixtures" \
    "${repo_root}/../network-labs/tests/fixtures" \
    "${repo_root}/../network-labs/fixtures" \
    "${repo_root}/../network-labs/examples"
}

_fixture_rel_candidates() {
  local rel="$1"
  local base
  base="$(basename "${rel}")"

  printf '%s\n' "${rel}"

  if [[ "${base}" != "${rel}" ]]; then
    printf '%s\n' "${base}"
  fi
}

resolve_fixture_dir_into() {
  local __outvar="$1"
  local rel="$2"
  local candidate
  local root
  local rel_candidate
  local -a checked=()

  while IFS= read -r root; do
    [[ -d "${root}" ]] || continue

    while IFS= read -r rel_candidate; do
      candidate="${root}/${rel_candidate}"
      checked+=("${candidate}")
      if [[ -d "${candidate}" ]]; then
        printf -v "${__outvar}" '%s' "${candidate}"
        return 0
      fi
    done < <(_fixture_rel_candidates "${rel}")
  done < <(_fixture_roots)

  fail "FAIL missing fixture dir for '${rel}' (checked: ${checked[*]})"
}

resolve_fixture_file_into() {
  local __outvar="$1"
  local rel="$2"
  local candidate
  local root
  local rel_candidate
  local -a checked=()

  while IFS= read -r root; do
    [[ -d "${root}" ]] || continue

    while IFS= read -r rel_candidate; do
      candidate="${root}/${rel_candidate}"
      checked+=("${candidate}")
      if [[ -f "${candidate}" ]]; then
        printf -v "${__outvar}" '%s' "${candidate}"
        return 0
      fi
    done < <(_fixture_rel_candidates "${rel}")
  done < <(_fixture_roots)

  fail "FAIL missing fixture file for '${rel}' (checked: ${checked[*]})"
}

build_control_plane_json() {
  local intent_path="$1"
  local inventory_path="$2"
  local output_path="$3"

  REPO_ROOT="${repo_root}" \
  NIX_SYSTEM_VALUE="${system}" \
  INTENT_PATH="${intent_path}" \
  INVENTORY_PATH="${inventory_path}" \
  nix eval --show-trace --impure --json \
    --file "${nix_test_dir}/build-control-plane-from-paths.nix" \
    > "${output_path}"
}

extract_artifacts_to_dir() {
  local intent_path="$1"
  local inventory_path="$2"
  local out_dir="$3"

  local tmp_dir
  tmp_dir="$(mktemp -d "${TMPDIR:-/tmp}/network-renderer-nixos-test-artifacts.XXXXXX")"
  trap 'rm -rf "${tmp_dir}"' RETURN

  mkdir -p "${tmp_dir}"

  REPO_ROOT="${repo_root}" \
  NIX_SYSTEM_VALUE="${system}" \
  INTENT_PATH="${intent_path}" \
  INVENTORY_PATH="${inventory_path}" \
  nix eval --show-trace --impure --json \
    --file "${nix_test_dir}/artifact-source-map-from-paths.nix" \
  | jq -r 'to_entries | sort_by(.key)[] | [.key, .value] | @tsv' \
  | while IFS=$'\t' read -r etc_path source_path; do
      local rel
      local target
      rel="${etc_path#/}"
      target="${tmp_dir}/${rel}"
      mkdir -p "$(dirname "${target}")"
      ln -sf "${source_path}" "${target}"
    done

  rm -rf "${out_dir}"
  mkdir -p "$(dirname "${out_dir}")"
  mv "${tmp_dir}" "${out_dir}"
  trap - RETURN
}

eval_renderer_json() {
  local mode="$1"
  local intent_path="$2"
  local inventory_path="$3"
  local box_name="$4"
  local output_path="$5"

  REPO_ROOT="${repo_root}" \
  NIX_SYSTEM_VALUE="${system}" \
  RENDER_MODE="${mode}" \
  INTENT_PATH="${intent_path}" \
  INVENTORY_PATH="${inventory_path}" \
  BOX_NAME="${box_name}" \
  nix eval --show-trace --impure --json \
    --file "${nix_test_dir}/render-from-paths.nix" \
    > "${output_path}"
}
