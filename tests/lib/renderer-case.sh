#!/usr/bin/env bash

set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/test-common.sh"

render_case_jsons() {
  local intent_path="$1"
  local inventory_path="$2"
  local box_name="$3"
  local tmp_dir="$4"

  build_control_plane_json "${intent_path}" "${inventory_path}" "${tmp_dir}/control-plane-output.json"
  eval_renderer_json host "${intent_path}" "${inventory_path}" "${box_name}" "${tmp_dir}/host.json"
  eval_renderer_json bridges "${intent_path}" "${inventory_path}" "${box_name}" "${tmp_dir}/bridges.json"
  eval_renderer_json containers "${intent_path}" "${inventory_path}" "${box_name}" "${tmp_dir}/containers.json"
  eval_renderer_json artifacts "${intent_path}" "${inventory_path}" "${box_name}" "${tmp_dir}/artifacts.json"
}

run_renderer_case_from_paths() {
  local name="$1"
  local intent_path="$2"
  local inventory_path="$3"
  local box_name="$4"
  local validator="$5"

  log "Running ${name}"

  local tmp_dir
  tmp_dir="$(mktemp -d "${TMPDIR:-/tmp}/network-renderer-nixos-case.XXXXXX")"

  if ! render_case_jsons "${intent_path}" "${inventory_path}" "${box_name}" "${tmp_dir}"; then
    echo "--- CONTROL PLANE OUTPUT ---"
    cat "${tmp_dir}/control-plane-output.json"
    rm -rf "${tmp_dir}"
    fail "FAIL ${name}: renderer evaluation failed"
  fi

  if ! "${repo_root}/tests/renderers/${validator}.sh" \
      "${tmp_dir}/host.json" \
      "${tmp_dir}/bridges.json" \
      "${tmp_dir}/containers.json" \
      "${tmp_dir}/artifacts.json"; then
    echo "--- CONTROL PLANE OUTPUT ---"
    cat "${tmp_dir}/control-plane-output.json"
    rm -rf "${tmp_dir}"
    fail "FAIL ${name}: renderer validation failed"
  fi

  rm -rf "${tmp_dir}"
  pass "${name}"
}
