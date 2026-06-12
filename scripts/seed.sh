#!/usr/bin/env bash
# scripts/seed.sh — Generate cached CPM fixtures for NixOS renderer tests.
#
# Usage:
#   scripts/seed.sh <name> <intent.nix> <inventory.nix>
#
#   scripts/seed.sh --check <name>
#
# Pipeline: compiler → NFM → CPM → cached JSON fixtures
# Output:  tests/fixtures/<name>/intent.json
#          tests/fixtures/<name>/inventory.json
#          tests/fixtures/<name>/control-plane.json (full CPM output)
#
# Idempotent: skips generation if fixtures already exist.
# Use --force to regenerate.

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
fixtures_dir="${repo_root}/tests/fixtures"

log()  { echo "==> $*"; }
warn() { echo "WARN: $*" >&2; }
die()  { echo "FATAL: $*" >&2; exit 1; }

usage() {
  cat >&2 <<'EOF'
Usage:
  scripts/seed.sh <name> <intent.nix> <inventory.nix>
  scripts/seed.sh --check <name>
  scripts/seed.sh --force <name> <intent.nix> <inventory.nix>

Generate cached CPM fixtures for renderer tests. The pipeline runs
compiler → forwarding-model → control-plane-model and saves the output
as JSON fixtures under tests/fixtures/<name>/.

Options:
  --check    Exit 0 if fixtures exist, 1 if not (no generation).
  --force    Regenerate even if fixtures already exist.
  --help     Show this message.
EOF
  exit 1
}

# --- argument parsing ---
mode="generate"
force=false
check_name=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --force) force=true; shift ;;
    --check) mode="check"; check_name="$2"; shift 2 ;;
    --help|-h) usage ;;
    -*) die "unknown option: $1" ;;
    *) break ;;
  esac
done

if [[ "$mode" == "check" ]]; then
  if [[ -z "$check_name" ]]; then
    die "--check requires a fixture name"
  fi
  fixture_dir="${fixtures_dir}/${check_name}"
  if [[ -f "${fixture_dir}/intent.json" && -f "${fixture_dir}/inventory.json" ]]; then
    log "fixtures exist: ${fixture_dir}"
    exit 0
  else
    warn "fixtures missing: ${fixture_dir}"
    exit 1
  fi
fi

if [[ $# -lt 3 ]]; then
  usage
fi

name="$1"
intent_path="$2"
inventory_path="$3"

# --- validation ---
[[ -f "$intent_path" ]]   || die "intent file not found: ${intent_path}"
[[ -f "$inventory_path" ]] || die "inventory file not found: ${inventory_path}"

fixture_dir="${fixtures_dir}/${name}"

if [[ -f "${fixture_dir}/intent.json" && -f "${fixture_dir}/inventory.json" && "$force" != "true" ]]; then
  log "fixtures already exist (use --force to regenerate): ${fixture_dir}"
  exit 0
fi

mkdir -p "$fixture_dir"

# --- resolve absolute paths ---
intent_abs="$(realpath "$intent_path")"
inventory_abs="$(realpath "$inventory_path")"

log "generating fixtures: ${name}"
log "  intent:    ${intent_abs}"
log "  inventory: ${inventory_abs}"
log "  output:    ${fixture_dir}"

# --- run pipeline: compiler → NFM → CPM ---
# buildControlPlaneFromPaths internally runs the full pipeline
tmp_dir="$(mktemp -d)"
trap 'rm -rf "${tmp_dir}"' EXIT

cpm_json="${tmp_dir}/cpm.json"

log "running CPM pipeline (compiler → NFM → CPM) ..."
REPO_ROOT="${repo_root}" \
INTENT_PATH="${intent_abs}" \
INVENTORY_PATH="${inventory_abs}" \
nix eval \
  --extra-experimental-features 'nix-command flakes' \
  --impure --json \
  --file "${repo_root}/tests/nix/build-cpm-from-paths.nix" \
  > "$cpm_json"

log "CPM output: $(wc -c < "$cpm_json") bytes"

# --- extract intent/inventory from CPM output ---
# The CPM output contains the full control plane model; save it alongside
# extracted intent/inventory for targeted test consumption.

if command -v jq >/dev/null 2>&1; then
  JQ=jq
else
  JQ="nix run --no-write-lock-file --extra-experimental-features 'nix-command flakes' path:${repo_root}#jq --"
fi

# Save full CPM output
cp "$cpm_json" "${fixture_dir}/control-plane.json"

# Extract and save intent + inventory as separate JSON fixtures
$JQ '{intent: .data["esp0xdeadbeef"].site["site-a"]}' "$cpm_json" > "${fixture_dir}/intent.json" 2>/dev/null || {
  warn "could not extract intent from CPM output; saving full CPM output only"
  # Fallback: save full CPM output as both intent and inventory
  cp "$cpm_json" "${fixture_dir}/intent.json"
}

$JQ '{inventory: .data["esp0xdeadbeef"].site["site-a"]}' "$cpm_json" > "${fixture_dir}/inventory.json" 2>/dev/null || {
  warn "could not extract inventory from CPM output; saving full CPM output only"
  cp "$cpm_json" "${fixture_dir}/inventory.json"
}

# --- copy source files for provenance ---
cp "$intent_abs"   "${fixture_dir}/intent.nix"
cp "$inventory_abs" "${fixture_dir}/inventory.nix"

log "fixtures generated: ${fixture_dir}"
log "  intent.json:            $(wc -c < "${fixture_dir}/intent.json") bytes"
log "  inventory.json:          $(wc -c < "${fixture_dir}/inventory.json") bytes"
log "  control-plane.json:     $(wc -c < "${fixture_dir}/control-plane.json") bytes"
log "  intent.nix (source):    $(wc -c < "${fixture_dir}/intent.nix") bytes"
log "  inventory.nix (source): $(wc -c < "${fixture_dir}/inventory.nix") bytes"
