#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

log() { echo "==> $*"; }
fail() { echo "$*" >&2; exit 1; }
pass() { echo "PASS $*"; }

_jq() {
  if command -v jq >/dev/null 2>&1; then
    jq "$@"
  else
    nix run \
      --no-write-lock-file \
      --extra-experimental-features 'nix-command flakes' \
      "path:${repo_root}#jq" -- "$@"
  fi
}

nix_eval_json_or_fail() {
  local label="$1"
  local output_file="$2"
  local stderr_file="$3"
  shift 3

  if ! "$@" >"$output_file" 2>"$stderr_file"; then
    echo "FAIL ${label}: nix eval crashed" >&2
    cat "$stderr_file" >&2
    exit 1
  fi
}

assert_json_checks_ok() {
  local label="$1"
  local result_json="$2"

  if [[ "$(_jq -r '.ok' "$result_json")" != "true" ]]; then
    echo "FAIL ${label}: failed checks" >&2
    _jq -r '.failed[]' "$result_json" >&2
    echo "full check state:" >&2
    _jq -S '.checks' "$result_json" >&2
    exit 1
  fi
}

nix_eval_true_or_fail() {
  local label="$1"
  shift

  local output_file
  local stderr_file
  output_file="$(mktemp)"
  stderr_file="$(mktemp)"

  if ! "$@" >"$output_file" 2>"$stderr_file"; then
    echo "FAIL ${label}: nix eval crashed" >&2
    cat "$stderr_file" >&2
    rm -f "$output_file" "$stderr_file"
    exit 1
  fi

  if ! grep -qx true "$output_file"; then
    echo "FAIL ${label}: expected nix eval to return true" >&2
    echo "stdout:" >&2
    cat "$output_file" >&2
    if [[ -s "$stderr_file" ]]; then
      echo "stderr:" >&2
      cat "$stderr_file" >&2
    fi
    rm -f "$output_file" "$stderr_file"
    exit 1
  fi

  rm -f "$output_file" "$stderr_file"
}

flake_input_path() {
  local input_name="$1"

  nix flake archive --json "path:${repo_root}" \
    | _jq -er ".inputs[\"${input_name}\"].path"
}

should_dump_on_warning() {
  local stderr_file="$1"
  grep -qF "advertisement still defaults from renderer policy" "$stderr_file"
}

archive_json_artifacts() {
  local label="$1"
  local json_dir="$2"

  local ts
  ts="$(date -u +%Y%m%dT%H%M%SZ)"
  local out_dir="${repo_root}/work/warnings/${label}/${ts}"

  mkdir -p "$out_dir"
  find "$json_dir" -maxdepth 1 -type f -name '*.json' -print0 \
    | sort -z \
    | while IFS= read -r -d '' f; do
        cp -f "$f" "$out_dir/$(basename "$f")"
      done

  log "Archived JSON artifacts to: ${out_dir}"
}

has_advertisement_default_alarm() {
  local render_json="$1"
  _jq -e '
    [
      .containers
      | to_entries[]
      | .value
      | to_entries[]
      | .value
      | ((.alarms? // []) | map(select(.alarmId == "access-dhcp4-derived" or .alarmId == "access-radvd-derived")) | length) > 0
    ]
    | any
  ' "$render_json" >/dev/null 2>&1
}

has_render_warnings_or_alarms() {
  local render_json="$1"

  _jq -e '
    [
      ..
      | objects
      | select(
          ((.alarms? // []) | length > 0)
          or ((.warnings? // []) | length > 0)
          or ((.warningMessages? // []) | length > 0)
        )
    ]
    | length > 0
  ' "$render_json" >/dev/null
}

assert_clean_render_contract() {
  local label="$1"
  local render_json="$2"
  local stderr_file="${3:-}"

  if [[ -n "$stderr_file" && -f "$stderr_file" ]] && rg -qF "evaluation warning:" "$stderr_file"; then
    cat "$stderr_file" >&2
    fail "FAIL ${label}: renderer emitted Nix evaluation warnings"
  fi

  if has_render_warnings_or_alarms "$render_json"; then
    _jq '
      [
        paths(objects) as $p
        | getpath($p)
        | select(
            ((.alarms? // []) | length > 0)
            or ((.warnings? // []) | length > 0)
            or ((.warningMessages? // []) | length > 0)
          )
        | {
            path: $p,
            alarms: (.alarms? // []),
            warnings: (.warnings? // []),
            warningMessages: (.warningMessages? // [])
          }
      ]
    ' "$render_json" >&2
    fail "FAIL ${label}: renderer produced alarms or warnings"
  fi
}

resolve_fixture_dir_into() {
  local __outvar="$1"
  local rel="$2"

  local candidate="${repo_root}/tests/fixtures/${rel}"
  if [[ -d "$candidate" ]]; then
    printf -v "$__outvar" '%s' "$candidate"
    return 0
  fi

  fail "missing fixture dir: ${rel} (expected ${candidate})"
}

build_cpm_json() {
  local intent_path="$1"
  local inventory_path="$2"
  local output_path="$3"

  REPO_ROOT="${repo_root}" \
  INTENT_PATH="${intent_path}" \
  INVENTORY_PATH="${inventory_path}" \
  nix eval \
    --extra-experimental-features 'nix-command flakes' \
    --impure --json \
    --file "${repo_root}/tests/nix/build-cpm-from-paths.nix" \
    > "${output_path}"

  local out_dir
  out_dir="$(dirname "${output_path}")"

  # Keep tests self-contained by copying inputs next to generated artifacts.
  # If the selected inventory is a wrapper (e.g. inventory-nixos.nix importing
  # ./inventory-base.nix or ./inventory.nix), copy sibling files too so relative
  # imports still resolve inside the temp output directory.
  local inv_to_copy="${inventory_path}"
  if [[ "$(basename "${inventory_path}")" == "inventory-nixos.nix" ]]; then
    local sibling
    local sibling_base
    sibling="$(dirname "${inventory_path}")/inventory.nix"
    sibling_base="$(dirname "${inventory_path}")/inventory-base.nix"
    cp -f "${inventory_path}" "${out_dir}/inventory-nixos.nix"
    if [[ -f "${sibling_base}" ]]; then
      cp -f "${sibling_base}" "${out_dir}/inventory-base.nix"
      inv_to_copy="${sibling_base}"
    elif [[ -f "${sibling}" ]]; then
      inv_to_copy="${sibling}"
    fi
  fi

  cp -f "${inv_to_copy}" "${out_dir}/inventory.nix"
  cp -f "${intent_path}" "${out_dir}/intent.nix"
}
