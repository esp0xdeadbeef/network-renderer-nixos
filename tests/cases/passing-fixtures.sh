#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "${repo_root}/tests/lib/test-common.sh"

render_fixture() {
  local rel="$1"
  local fixture_dir
  resolve_fixture_dir_into fixture_dir "$rel"

  local intent_nix="${fixture_dir}/intent.nix"
  local inventory_nix="${fixture_dir}/inventory-nixos.nix"
  if [[ ! -f "$intent_nix" ]]; then
    fail "FAIL $(basename "$rel"): missing intent.nix"
  fi
  if [[ ! -f "$inventory_nix" ]]; then
    fail "FAIL $(basename "$rel"): missing inventory-nixos.nix"
  fi

  local tmp_dir
  tmp_dir="$(mktemp -d "${TMPDIR:-/tmp}/network-renderer-nixos-fixture.XXXXXX")"
  trap 'rm -rf "${tmp_dir}"' RETURN

  (
    cd "${tmp_dir}"
    build_cpm_json "${intent_nix}" "${inventory_nix}" "${tmp_dir}/cpm.json"

    nix run \
      --no-write-lock-file \
      --extra-experimental-features 'nix-command flakes' \
      "${repo_root}"#render-dry-config \
      -- \
      --debug \
      "${tmp_dir}/cpm.json" \
      >/dev/null \
      2> >(tee "${tmp_dir}/render.stderr" >&2)

    # Policy endpoint binding gaps should be a hard error (not a warning / partial render).
    if rg -qF "firewall-policy-endpoint-bindings-missing" "${tmp_dir}/render.stderr"; then
      fail "FAIL $(basename "${rel}"): policy endpoint bindings were not authoritative"
    fi

    if should_dump_on_warning "${tmp_dir}/render.stderr"; then
      archive_json_artifacts "$(basename "${rel}")" "${tmp_dir}"
    fi
    if has_advertisement_default_alarm ./90-render.json; then
      archive_json_artifacts "$(basename "${rel}")" "${tmp_dir}"
    fi

    assert_clean_render_contract "$(basename "${rel}")" ./90-render.json "${tmp_dir}/render.stderr"

    "${repo_root}/test-split-box-render.sh" "${tmp_dir}/cpm.json" ./90-render.json >/dev/null
  )

  trap - RETURN
  rm -rf "${tmp_dir}"
  pass "$(basename "$rel")"
}

default_fixtures=(
  "passing/s-router-test"
)

selected_fixtures=()

if (( $# > 0 )); then
  for requested in "$@"; do
    case "${requested}" in
      passing/*)
        selected_fixtures+=("${requested}")
        ;;
      *)
        selected_fixtures+=("passing/${requested}")
        ;;
    esac
  done
else
  selected_fixtures=("${default_fixtures[@]}")
fi

for fixture_rel in "${selected_fixtures[@]}"; do
  log "Running $(basename "${fixture_rel}")"
  render_fixture "${fixture_rel}"
done
