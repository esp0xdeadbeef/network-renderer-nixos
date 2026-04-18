#!/usr/bin/env bash
set -euo pipefail

if [ "$#" -gt 1 ]; then
  echo "usage: ./render-all.sh [path-to-network-labs-or-examples]" >&2
  exit 1
fi

search_root="${1:-../network-labs}"
search_root="$(realpath "$search_root")"

if [ ! -d "$search_root" ]; then
  echo "[!] Missing directory: $search_root" >&2
  exit 1
fi

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

should_dump_on_warning() {
  local stderr_file="$1"
  grep -qF "advertisement still defaults from renderer policy" "$stderr_file"
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

compile_cpm() {
  local intent_path="$1"
  local inventory_path="$2"
  local output_path="$3"

  REPO_ROOT="$repo_root" \
  INTENT_PATH="$intent_path" \
  INVENTORY_PATH="$inventory_path" \
  nix eval \
    --extra-experimental-features 'nix-command flakes' \
    --impure --json \
    --file "$repo_root/tools/nix/build-cpm-from-paths.nix" \
    > "$output_path"
}

failed=false

mapfile -t intent_paths < <(find "$search_root" -name intent.nix -type f | sort)

if (( ${#intent_paths[@]} == 0 )); then
  echo "[!] No intent.nix files found under: $search_root" >&2
  exit 1
fi

echo "[*] Found ${#intent_paths[@]} intent.nix files under: $search_root"

for intent_path in "${intent_paths[@]}"; do
  inventory_path="$(dirname "$intent_path")/inventory.nix"
  if [ ! -f "$inventory_path" ]; then
    continue
  fi

  echo "[*] Running for $intent_path"

  rm -f \
    ./00-*.json \
    ./01-*.json \
    ./02-*.json \
    ./03-*.json \
    ./04-*.json \
    ./05-*.json \
    ./10-*.json \
    ./11-*.json \
    ./25-*.json \
    ./30-*.json \
    ./31-*.json \
    ./32-*.json \
    ./35-*.json \
    ./90-*.json

  tmp_dir="$(mktemp -d "${TMPDIR:-/tmp}/network-renderer-nixos-render-all.XXXXXX")"

  if ! compile_cpm "$intent_path" "$inventory_path" "$tmp_dir/cpm.json"; then
    echo
    echo "[!] CPM compilation failed for: $intent_path"
    failed=true
    rm -rf "$tmp_dir"
    continue
  fi

  if ! nix run \
    --no-write-lock-file \
    --extra-experimental-features 'nix-command flakes' \
    .#render-dry-config \
    -- \
    --debug \
    "$tmp_dir/cpm.json" \
    2> >(tee "$tmp_dir/render.stderr" >&2)
  then
    echo
    echo "[!] Generation failed for: $intent_path"
    dump_generated_artifacts
    failed=true
    rm -rf "$tmp_dir"
    continue
  fi

  if should_dump_on_warning "$tmp_dir/render.stderr"; then
    archive_generated_artifacts "$(basename "$(dirname "$intent_path")")"
    dump_generated_artifacts
  fi

  if has_advertisement_default_alarm; then
    archive_generated_artifacts "$(basename "$(dirname "$intent_path")")"
    dump_generated_artifacts
  fi

  if ! ./test-split-box-render.sh "$tmp_dir/cpm.json" ./90-render.json; then
    echo
    echo "[!] Split box renderer validation failed for: $intent_path"
    dump_generated_artifacts
    failed=true
    rm -rf "$tmp_dir"
    continue
  fi

  rm -rf "$tmp_dir"
done

if [ "$failed" = true ]; then
  echo
  echo "[!] render-all.sh completed with failures" >&2
  exit 1
fi
