#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat >&2 <<'EOF'
usage:
  ./check-artifacts.sh [out-dir]
  ./check-artifacts.sh [out-dir] --cpm <control-plane.(nix|json)>

Behavior:
  - Runs the legacy/s88 renderer entrypoint (`.#render-dry-config`) in a temp dir.
  - Copies the generated JSON artifacts into <out-dir>/network-artifacts/ and lists them.

Defaults:
  - If no paths are provided, loads cpmPath OR (intentPath + inventoryPath) from
    ./vm-input-test.nix if it exists, otherwise from ./vm-input-home.nix.
EOF
}

out_dir="./work/etc"
if [[ $# -gt 0 && "$1" != --* ]]; then
  out_dir="$1"
  shift
fi

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

intent_path=""
inventory_path=""
cpm_path=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    -h|--help)
      usage
      exit 0
      ;;
    --cpm)
      cpm_path="${2:-}"
      shift 2
      ;;
    *)
      echo "[!] Unknown argument: $1" >&2
      usage
      exit 1
      ;;
  esac
done

tmp_dir="$(mktemp -d "${TMPDIR:-/tmp}/network-renderer-nixos-artifacts.XXXXXX")"
trap 'rm -rf "$tmp_dir"' EXIT

resolve_default_inputs() {
  local input_file=""
  if [[ -f ./vm-input-test.nix ]]; then
    input_file="./vm-input-test.nix"
  elif [[ -f ./vm-input-home.nix ]]; then
    input_file="./vm-input-home.nix"
  else
    echo "[!] Missing default input file: ./vm-input-test.nix or ./vm-input-home.nix" >&2
    exit 1
  fi

  local paths_json
  paths_json="$(
    nix eval \
      --extra-experimental-features 'nix-command flakes' \
      --impure --json \
      --expr "let i = import ${input_file}; in {
        cpmPath = if i ? cpmPath then toString i.cpmPath else null;
        intentPath = if i ? intentPath then toString i.intentPath else null;
        inventoryPath = if i ? inventoryPath then toString i.inventoryPath else null;
      }"
  )"

  cpm_path="$(jq -r '.cpmPath // empty' <<<"$paths_json")"
  intent_path="$(jq -r '.intentPath // empty' <<<"$paths_json")"
  inventory_path="$(jq -r '.inventoryPath // empty' <<<"$paths_json")"
}

if [[ -z "$cpm_path" ]]; then
  resolve_default_inputs
fi

if [[ -z "$cpm_path" && -z "$intent_path" && -z "$inventory_path" ]]; then
  echo "[!] Missing inputs: provide --cpm or set cpmPath, or (intentPath + inventoryPath) in vm-input.*.nix" >&2
  usage
  exit 1
fi

(
  cd "$tmp_dir"

  if [[ -z "$cpm_path" ]]; then
    REPO_ROOT="${repo_root}" \
    INTENT_PATH="$(realpath "$intent_path")" \
    INVENTORY_PATH="$(realpath "$inventory_path")" \
    nix eval \
      --extra-experimental-features 'nix-command flakes' \
      --impure --json \
      --file "${repo_root}/tools/nix/build-cpm-from-paths.nix" \
      > "${tmp_dir}/cpm.json"
    cpm_path="${tmp_dir}/cpm.json"
  fi

  nix run \
    --no-write-lock-file \
    --extra-experimental-features 'nix-command flakes' \
    "${repo_root}"#render-dry-config \
    -- --debug "$(realpath "$cpm_path")"
) || {
  echo "[!] render-dry-config failed. Dumping any generated JSON artifacts (if present):" >&2
  (ls -1 "$tmp_dir"/*.json 2>/dev/null || true) | sed 's/^/[!]   /' >&2
  exit 1
}

rm -rf "$out_dir/network-artifacts"
mkdir -p "$out_dir/network-artifacts"

# Copy everything that render-dry-config emitted. Keep filenames stable for diffs.
find "$tmp_dir" -maxdepth 1 -type f -name '*.json' -print0 \
  | sort -z \
  | while IFS= read -r -d '' f; do
      cp -f "$f" "$out_dir/network-artifacts/$(basename "$f")"
    done

find "$out_dir/network-artifacts" -type f -name '*.json' | sort
