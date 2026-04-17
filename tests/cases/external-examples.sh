#!/usr/bin/env bash

set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib/test-common.sh"

run_external_examples() {
  if [[ "${SKIP_EXTERNAL_EXAMPLES:-0}" == "1" ]]; then
    return 0
  fi

  if [[ ! -d "${examples_root}" ]]; then
    log "Skipping external examples (missing ${examples_root})"
    return 0
  fi

  log "Running external examples"

  find "${examples_root}" -mindepth 1 -maxdepth 1 -type d | sort | while read -r dir; do
    local name
    local intent
    local inventory
    local tmp_dir

    name="$(basename "${dir}")"
    intent="${dir}/intent.nix"
    inventory="${dir}/inventory.nix"

    [[ -f "${intent}" ]] || continue
    [[ -f "${inventory}" ]] || continue

    log "Example ${name}"

    tmp_dir="$(mktemp -d "${TMPDIR:-/tmp}/network-renderer-nixos-example.XXXXXX")"

    build_control_plane_json "${intent}" "${inventory}" "${tmp_dir}/control-plane-output.json"

    if ! extract_artifacts_to_dir "${intent}" "${inventory}" "${tmp_dir}/out"; then
      echo "--- CONTROL PLANE OUTPUT ---"
      cat "${tmp_dir}/control-plane-output.json"
      rm -rf "${tmp_dir}"
      fail "FAIL network-labs-example:${name}: artifact extraction failed"
    fi

    if ! "${repo_root}/tests/renderers/external-example.sh" "${tmp_dir}/out"; then
      echo "--- CONTROL PLANE OUTPUT ---"
      cat "${tmp_dir}/control-plane-output.json"
      rm -rf "${tmp_dir}"
      fail "FAIL network-labs-example:${name}: extracted artifact tree validation failed"
    fi

    rm -rf "${tmp_dir}"
    pass "network-labs-example:${name}"
  done
}

run_external_examples
