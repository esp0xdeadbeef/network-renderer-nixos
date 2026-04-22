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

  # render-dry-config resolves inventory relative to the CPM file's directory unless
  # an explicit inventoryPath is passed. Keep tests self-contained by copying the
  # inputs next to the generated CPM JSON.
  local out_dir
  out_dir="$(dirname "${output_path}")"

  # If the selected inventory is a wrapper (e.g. inventory-nixos.nix importing
  # ./inventory.nix), copying it to ./inventory.nix would self-import and blow up.
  local inv_to_copy="${inventory_path}"
  if [[ "$(basename "${inventory_path}")" == "inventory-nixos.nix" ]]; then
    local sibling
    sibling="$(dirname "${inventory_path}")/inventory.nix"
    cp -f "${inventory_path}" "${out_dir}/inventory-nixos.nix"
    if [[ -f "${sibling}" ]]; then
      inv_to_copy="${sibling}"
    fi
  fi

  cp -f "${inv_to_copy}" "${out_dir}/inventory.nix"
  cp -f "${intent_path}" "${out_dir}/intent.nix"
}
