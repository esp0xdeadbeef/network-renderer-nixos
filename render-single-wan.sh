#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

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

dump_generated_artifacts() {
  echo
  echo "[!] Dumping generated JSON artifacts:"
  echo

  for j in ./[0-9][0-9]-*.json; do
    [ -e "$j" ] || continue
    echo "===== $j ====="
    _jq -c . "$j" 2>/dev/null || cat "$j"
    echo
  done
}

archive_generated_artifacts() {
  local label="$1"
  local ts
  ts="$(date -u +%Y%m%dT%H%M%SZ)"
  local out_dir="${repo_root}/work/warnings/${label}/${ts}"

  mkdir -p "$out_dir"
  for j in ./[0-9][0-9]-*.json; do
    [ -e "$j" ] || continue
    cp -f "$j" "${out_dir}/$(basename "$j")"
  done

  echo
  echo "[!] Archived JSON artifacts to: ${out_dir}"
}

has_advertisement_default_alarm() {
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
  ' ./90-render.json >/dev/null 2>&1
}

labs_root="$(
  nix flake archive --json "path:${repo_root}" \
    | _jq -er '.inputs["network-labs"].path'
)"
lab_root="${labs_root}/examples/single-wan"

intent_path="$(realpath "${lab_root}/intent.nix")"
inventory_path="${lab_root}/inventory-nixos.nix"
if [[ ! -f "${inventory_path}" ]]; then
  inventory_path="${lab_root}/inventory.nix"
fi
inventory_path="$(realpath "${inventory_path}")"

if [[ ! -f "$intent_path" ]]; then
  echo "[!] Missing intent.nix: ${intent_path}" >&2
  exit 1
fi
if [[ ! -f "$inventory_path" ]]; then
  echo "[!] Missing inventory.nix: ${inventory_path}" >&2
  exit 1
fi

tmp_dir="$(mktemp -d "${TMPDIR:-/tmp}/network-renderer-nixos-single-wan.XXXXXX")"
trap 'rm -rf "$tmp_dir"' EXIT

REPO_ROOT="$repo_root" \
INTENT_PATH="$intent_path" \
INVENTORY_PATH="$inventory_path" \
nix eval --extra-experimental-features 'nix-command flakes' --impure --json \
  --file "$repo_root/tools/nix/build-cpm-from-paths.nix" \
  > "$tmp_dir/cpm.json"

nix run \
  --no-write-lock-file \
  --extra-experimental-features 'nix-command flakes' \
  .#render-dry-config \
  -- \
  --debug \
  "$tmp_dir/cpm.json" \
  2> >(tee "$tmp_dir/render.stderr" >&2)

if grep -qF "advertisement still defaults from renderer policy" "$tmp_dir/render.stderr"; then
  archive_generated_artifacts "single-wan"
  dump_generated_artifacts
fi

if [ ! -f ./90-render.json ]; then
  if [ -f ./90-dry-config.json ]; then
    _jq '.render' ./90-dry-config.json > ./90-render.json
  else
    echo "[!] Missing render artifact: ./90-render.json" >&2
    exit 1
  fi
fi

if has_advertisement_default_alarm; then
  archive_generated_artifacts "single-wan"
  dump_generated_artifacts
fi

./test-split-box-render.sh "$tmp_dir/cpm.json" ./90-render.json

_jq -c . ./90-render.json
