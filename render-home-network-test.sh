#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

dump_generated_artifacts() {
  echo
  echo "[!] Dumping generated JSON artifacts:"
  echo

  for j in ./[0-9][0-9]-*.json; do
    [ -e "$j" ] || continue
    echo "===== $j ====="
    jq -c . "$j" 2>/dev/null || cat "$j"
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
  jq -e '
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

intent_path="$(nix eval --extra-experimental-features 'nix-command flakes' --impure --raw --expr 'toString (import ./vm-input-test.nix).intentPath')"
inventory_path="$(nix eval --extra-experimental-features 'nix-command flakes' --impure --raw --expr 'toString (import ./vm-input-test.nix).inventoryPath')"

tmp_dir="$(mktemp -d "${TMPDIR:-/tmp}/network-renderer-nixos-home-test.XXXXXX")"
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
  archive_generated_artifacts "home-network-test"
  dump_generated_artifacts
fi

if [ ! -f ./90-render.json ]; then
  if [ -f ./90-dry-config.json ]; then
    jq '.render' ./90-dry-config.json > ./90-render.json
  else
    echo "[!] Missing render artifact: ./90-render.json" >&2
    exit 1
  fi
fi

if has_advertisement_default_alarm; then
  archive_generated_artifacts "home-network-test"
  dump_generated_artifacts
fi

./test-split-box-render.sh "$tmp_dir/cpm.json" ./90-render.json

jq -c . ./90-render.json
