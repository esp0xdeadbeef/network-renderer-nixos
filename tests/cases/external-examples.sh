#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "${repo_root}/tests/lib/test-common.sh"

search_root="${1:-${repo_root}/../network-labs}"
search_root="$(realpath "$search_root")"

if [[ ! -d "$search_root" ]]; then
  fail "missing network-labs directory: ${search_root}"
fi

mapfile -t intent_paths < <(find "$search_root" -type f -name intent.nix | sort)

if (( ${#intent_paths[@]} == 0 )); then
  fail "no intent.nix files found under: ${search_root}"
fi

log "Scanning ${#intent_paths[@]} intent.nix files under: ${search_root}"

ran=0
skipped=0

for intent_path in "${intent_paths[@]}"; do
  inventory_path="$(dirname "$intent_path")/inventory.nix"
  if [[ ! -f "$inventory_path" ]]; then
    skipped=$((skipped + 1))
    continue
  fi

  ran=$((ran + 1))
  log "Running $(dirname "$intent_path")"

  tmp_dir="$(mktemp -d "${TMPDIR:-/tmp}/network-renderer-nixos-external.XXXXXX")"
  trap 'rm -rf "${tmp_dir}"' RETURN

  (
    cd "${tmp_dir}"
    build_cpm_json "${intent_path}" "${inventory_path}" "${tmp_dir}/cpm.json"

    nix run \
      --no-write-lock-file \
      --extra-experimental-features 'nix-command flakes' \
      "${repo_root}"#render-dry-config \
      -- \
      --debug \
      "${tmp_dir}/cpm.json" \
      >/dev/null \
      2> >(tee "${tmp_dir}/render.stderr" >&2)

    if should_dump_on_warning "${tmp_dir}/render.stderr"; then
      archive_json_artifacts "$(basename "$(dirname "${intent_path}")")" "${tmp_dir}"
    fi
    if has_advertisement_default_alarm ./90-render.json; then
      archive_json_artifacts "$(basename "$(dirname "${intent_path}")")" "${tmp_dir}"
    fi

    "${repo_root}/test-split-box-render.sh" "${tmp_dir}/cpm.json" ./90-render.json >/dev/null
  )

  trap - RETURN
  rm -rf "${tmp_dir}"

  pass "$(dirname "$intent_path")"
done

if (( ran == 0 )); then
  fail "no runnable test cases found (need dirs containing both intent.nix and inventory.nix) under: ${search_root}"
fi

log "Completed: ran=${ran} skipped(no-inventory)=${skipped}"
