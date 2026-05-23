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
  )

  trap - RETURN
  rm -rf "${tmp_dir}"
  pass "$(basename "$rel")"
}

default_fixtures=(
  "passing/s-router-test"
)

if [[ "${NIXOS_RENDERER_FIXTURE_RUN_ONE:-0}" == "1" ]]; then
  render_fixture "${NIXOS_RENDERER_FIXTURE:?missing NIXOS_RENDERER_FIXTURE}"
  exit 0
fi

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

jobs="${TEST_JOBS:-$(nproc 2>/dev/null || getconf _NPROCESSORS_ONLN 2>/dev/null || printf '1')}"
if ! [[ "${jobs}" =~ ^[0-9]+$ ]] || ((jobs < 1)); then
  jobs=1
fi
timeout_seconds="${TEST_TIMEOUT_SECONDS:-${NETWORK_REPO_TEST_TIMEOUT_SECONDS:-1800}}"
tmp_logs="$(mktemp -d)"
running=0
status=0
declare -A pid_to_name=()
declare -A pid_to_log=()

finish_fixture() {
  local pid="$1"
  local rc="$2"
  local name="${pid_to_name[${pid}]}"
  local log_file="${pid_to_log[${pid}]}"

  if ((rc == 0)); then
    cat "${log_file}"
  else
    cat "${log_file}" >&2
    status=1
  fi
  unset "pid_to_name[${pid}]"
  unset "pid_to_log[${pid}]"
}

for fixture_rel in "${selected_fixtures[@]}"; do
  log "Running $(basename "${fixture_rel}")"
  log_file="${tmp_logs}/${fixture_rel//\//__}.log"
  NIXOS_RENDERER_FIXTURE_RUN_ONE=1 NIXOS_RENDERER_FIXTURE="${fixture_rel}" timeout "${timeout_seconds}" bash "${BASH_SOURCE[0]}" >"${log_file}" 2>&1 &
  pid_to_name[$!]="${fixture_rel}"
  pid_to_log[$!]="${log_file}"
  running=$((running + 1))

  if ((running >= jobs)); then
    rc=0
    wait -n -p finished_pid || rc=$?
    finish_fixture "${finished_pid}" "${rc}"
    running=$((running - 1))
  fi
done

while ((running > 0)); do
  rc=0
  wait -n -p finished_pid || rc=$?
  finish_fixture "${finished_pid}" "${rc}"
  running=$((running - 1))
done

rm -rf "${tmp_logs}"
exit "${status}"
