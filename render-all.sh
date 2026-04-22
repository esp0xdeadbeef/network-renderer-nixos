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

# Controls:
# - FAIL_ON_WARNINGS=1: treat evaluation warnings / warning alarms as failures.
# - FAIL_FAST=1: stop on first warning/failure instead of scanning everything.
fail_on_warnings="${FAIL_ON_WARNINGS:-0}"
fail_fast="${FAIL_FAST:-0}"

dump_generated_artifacts() {
  if [[ "${DUMP_JSON_ON_WARNINGS:-0}" != "1" ]]; then
    return 0
  fi

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
  local cpm_path="${2:-}"
  local stderr_path="${3:-}"
  local ts
  ts="$(date -u +%Y%m%dT%H%M%SZ)"
  local out_dir="${repo_root}/work/warnings/${label}/${ts}"

  mkdir -p "$out_dir"
  for j in ./[0-9][0-9]-*.json; do
    [ -e "$j" ] || continue
    cp -f "$j" "${out_dir}/$(basename "$j")"
  done

  if [[ -n "$cpm_path" && -f "$cpm_path" ]]; then
    cp -f "$cpm_path" "${out_dir}/cpm.json"
  fi
  if [[ -n "$stderr_path" && -f "$stderr_path" ]]; then
    cp -f "$stderr_path" "${out_dir}/render.stderr"
  fi

  echo
  echo "[!] Archived JSON artifacts to: ${out_dir}"
}

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "[!] Required command not found: $1" >&2
    exit 1
  }
}

fail_on_any_warning() {
  local stderr_file="$1"
  grep -qF "evaluation warning:" "$stderr_file"
}

has_any_warning_alarm() {
  jq -e '
    [
      .containers
      | to_entries[]
      | .value
      | to_entries[]
      | .value
      | (.alarms? // [])
      | map(select((.severity? == "warning") or (.isa182? != null and .isa182.category? == "warning")))
      | length > 0
    ]
    | any
  ' ./90-render.json >/dev/null 2>&1
}

summarize_warning_alarms() {
  jq -r '
    .containers
    | to_entries[]
    | .key as $host
    | .value
    | to_entries[]
    | .key as $container
    | .value
    | (.alarms? // [])
    | map(select((.severity? == "warning") or (.isa182? != null and .isa182.category? == "warning")))
    | .[]
    | "\($host)\t\($container)\t\(.alarmId)\t\(.summary)"
  ' ./90-render.json 2>/dev/null || true
}

gron_grep() {
  local json_path="$1"
  local pattern="$2"

  # Prefer gron for stable greps across depth changes.
  if command -v gron >/dev/null 2>&1; then
    # Treat pattern as a fixed string; callers shouldn't need to think about regex escaping.
    gron "$json_path" | rg -n -F "$pattern" || true
  else
    # Fallback: best-effort key scan via jq (less stable, but avoids a hard dependency).
    jq -r '..|objects|keys[]?' "$json_path" 2>/dev/null | rg -n -F "$pattern" || true
  fi
}

classify_alarm_sources() {
  local cpm_path="$1"
  local render_path="$2"

  echo
  echo "[!] Heuristic source check (UPSTREAM vs THIS-REPO) using CPM + render artifacts:"

  local alarm_ids
  alarm_ids="$(jq -r '
    .containers
    | to_entries[]
    | .value
    | to_entries[]
    | .value
    | (.alarms // [])
    | .[]
    | select((.severity? == "warning") or (.isa182? != null and .isa182.category? == "warning"))
    | .alarmId
  ' "$render_path" | sort -u)"

  if [[ -z "$alarm_ids" ]]; then
    echo "[!] No warning alarms found in render.json"
    return 0
  fi

  while IFS= read -r alarm_id; do
    [[ -n "$alarm_id" ]] || continue

    case "$alarm_id" in
      access-dhcp4-derived)
        if gron_grep "$cpm_path" ".advertisements.dhcp4[" | rg -q .; then
          echo "- $alarm_id: THIS-REPO (CPM already has advertisements.dhcp4[])"
        else
          echo "- $alarm_id: UPSTREAM (no CPM advertisements.dhcp4[] found)"
        fi
        ;;
      access-radvd-derived)
        if gron_grep "$cpm_path" ".advertisements.ipv6Ra[" | rg -q .; then
          echo "- $alarm_id: THIS-REPO (CPM already has advertisements.ipv6Ra[])"
        else
          echo "- $alarm_id: UPSTREAM (no CPM advertisements.ipv6Ra[] found)"
        fi
        ;;
      firewall-access-forwarding-defaults)
        if gron_grep "$cpm_path" ".forwardingIntent.rules[" | rg -q .; then
          echo "- $alarm_id: THIS-REPO (CPM already has forwardingIntent.rules[])"
        else
          echo "- $alarm_id: UPSTREAM (no CPM forwardingIntent.rules[] found)"
        fi
        ;;
      firewall-core-nat-defaults)
        if gron_grep "$cpm_path" ".natIntent.enabled" | rg -q .; then
          echo "- $alarm_id: THIS-REPO (CPM already has natIntent.*)"
        else
          echo "- $alarm_id: UPSTREAM (no CPM natIntent.* found)"
        fi
        ;;
      firewall-policy-endpoint-bindings-missing)
        # This alarm usually means: cannot bind tenants/upstream to *policy node interfaces*.
        # We can quickly tell whether the CPM is missing key binding/tag context.
        local have_endpoint_bindings have_canonical_tags have_contract_tags
        have_endpoint_bindings=0
        have_canonical_tags=0
        have_contract_tags=0

        if gron_grep "$cpm_path" ".policy.endpointBindings.tenants." | rg -q .; then
          have_endpoint_bindings=1
        fi
        if gron_grep "$cpm_path" ".policy.interfaceTags." | rg -q .; then
          have_canonical_tags=1
        fi
        if gron_grep "$cpm_path" ".communicationContract.interfaceTags." | rg -q .; then
          have_contract_tags=1
        fi

        if [[ "$have_endpoint_bindings" -eq 1 && "$have_canonical_tags" -eq 1 && "$have_contract_tags" -eq 1 ]]; then
          echo "- $alarm_id: THIS-REPO (CPM has endpointBindings + interfaceTags; binding logic likely wrong)"
        else
          echo "- $alarm_id: UPSTREAM (CPM missing tags/bindings needed for policy endpoint resolution)"
          [[ "$have_endpoint_bindings" -eq 1 ]] || echo "  - missing: policy.endpointBindings.tenants"
          [[ "$have_canonical_tags" -eq 1 ]] || echo "  - missing: site.policy.interfaceTags"
          [[ "$have_contract_tags" -eq 1 ]] || echo "  - missing: communicationContract.interfaceTags"
        fi
        ;;
      *)
        echo "- $alarm_id: UNKNOWN (no heuristic)"
        ;;
    esac
  done <<<"$alarm_ids"

  echo
  echo "[!] Useful CPM grep entrypoints (via gron):"
  echo "  advertisements:     gron cpm.json | rg '\\\\.advertisements\\\\.'"
  echo "  forwardingIntent:   gron cpm.json | rg '\\\\.forwardingIntent\\\\.'"
  echo "  natIntent:          gron cpm.json | rg '\\\\.natIntent\\\\.'"
  echo "  policy bindings:    gron cpm.json | rg '\\\\.policy\\\\.(endpointBindings|interfaceTags)\\\\.'"
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
  inventory_path="$(dirname "$intent_path")/inventory-nixos.nix"
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
    archive_generated_artifacts "$(basename "$(dirname "$intent_path")")" "$tmp_dir/cpm.json" "$tmp_dir/render.stderr"
    dump_generated_artifacts
  fi

  if has_advertisement_default_alarm; then
    archive_generated_artifacts "$(basename "$(dirname "$intent_path")")" "$tmp_dir/cpm.json" "$tmp_dir/render.stderr"
    dump_generated_artifacts
  fi

  if fail_on_any_warning "$tmp_dir/render.stderr" || has_any_warning_alarm; then
    echo
    echo "[!] Evaluation warnings detected for: $intent_path" >&2
    archive_generated_artifacts "$(basename "$(dirname "$intent_path")")" "$tmp_dir/cpm.json" "$tmp_dir/render.stderr"
    echo "[!] Warning alarms (host, container, alarmId, summary):" >&2
    summarize_warning_alarms | column -t -s $'\t' >&2 || true
    classify_alarm_sources "$tmp_dir/cpm.json" ./90-render.json >&2 || true
    dump_generated_artifacts
    if [[ "$fail_on_warnings" == "1" ]]; then
      failed=true
      rm -rf "$tmp_dir"
      if [[ "$fail_fast" == "1" ]]; then
        exit 1
      fi
      continue
    fi
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
