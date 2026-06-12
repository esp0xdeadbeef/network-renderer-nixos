#!/usr/bin/env bash
# run-all-tests.sh — Run all NixOS renderer tests asynchronously.
#
# Usage:
#   bash run-all-tests.sh
#
# Auto-discovers all tests in tests/test-*.sh, runs them in parallel,
# reports PASS/FAIL per test, and exits non-zero if any test fails.
#
# Environment:
#   TEST_JOBS              Max concurrent tests (default: nproc)
#   TEST_TIMEOUT_SECONDS    Per-test timeout (default: 1800)

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
test_dir="${repo_root}/tests"

# --- configuration ---
default_jobs="$(nproc 2>/dev/null || getconf _NPROCESSORS_ONLN 2>/dev/null || printf '1')"
jobs="${TEST_JOBS:-${default_jobs}}"
test_timeout_seconds="${TEST_TIMEOUT_SECONDS:-1800}"

if ! [[ "${jobs}" =~ ^[0-9]+$ ]] || [[ "${jobs}" -lt 1 ]]; then
  echo "error: TEST_JOBS must be a positive integer, got '${jobs}'" >&2
  exit 2
fi
if ! [[ "${test_timeout_seconds}" =~ ^[0-9]+$ ]] || [[ "${test_timeout_seconds}" -lt 1 ]]; then
  echo "error: TEST_TIMEOUT_SECONDS must be a positive integer, got '${test_timeout_seconds}'" >&2
  exit 2
fi

# --- discover tests ---
mapfile -t test_files < <(
  find "${test_dir}" -maxdepth 1 -type f -name 'test-*.sh' ! -name 'test.sh' -print0 \
    | sort -z \
    | xargs -0 -n1 echo
)

if [[ ${#test_files[@]} -eq 0 ]]; then
  echo "error: no test files found in ${test_dir}" >&2
  exit 2
fi

# --- run tests asynchronously ---
tmp_dir="$(mktemp -d)"
trap 'rm -rf "${tmp_dir}"' EXIT

declare -A pid_to_name=()
declare -A pid_to_log=()
declare -A pid_to_start=()
running=0
failures=0
passed=0

wait_for_one() {
  local finished_pid
  local status=0
  wait -n -p finished_pid || status=$?

  local name="${pid_to_name[${finished_pid}]}"
  local log_file="${pid_to_log[${finished_pid}]}"
  local start="${pid_to_start[${finished_pid}]}"
  local elapsed=$((SECONDS - start))
  unset "pid_to_name[${finished_pid}]"
  unset "pid_to_log[${finished_pid}]"
  unset "pid_to_start[${finished_pid}]"
  running=$((running - 1))

  if (( status == 0 )); then
    printf 'PASS %s (%ss)\n' "${name}" "${elapsed}"
    passed=$((passed + 1))
  else
    printf 'FAIL %s (exit %s, %ss)\n' "${name}" "${status}" "${elapsed}" >&2
    awk -v prefix="[${name}] " '{ print prefix $0 }' "${log_file}" >&2
    failures=$((failures + 1))
  fi
}

printf 'running %s tests with TEST_JOBS=%s\n' "${#test_files[@]}" "${jobs}"

for test_file in "${test_files[@]}"; do
  name="${test_file#${repo_root}/}"
  log_file="${tmp_dir}/${name//\//__}.log"
  printf 'START %s\n' "${name}"

  (
    timeout "${test_timeout_seconds}" bash -c '
      source "$1"
      set --
      source "$2"
    ' _ "${repo_root}/tests/lib/test-common.sh" "${test_file}"
  ) >"${log_file}" 2>&1 &

  pid_to_name[$!]="${name}"
  pid_to_log[$!]="${log_file}"
  pid_to_start[$!]="${SECONDS}"
  running=$((running + 1))

  if (( running >= jobs )); then
    wait_for_one
  fi
done

while (( running > 0 )); do
  wait_for_one
done

# --- report ---
total=$((passed + failures))
printf '\n%s/%s tests passed\n' "${passed}" "${total}"

if (( failures > 0 )); then
  printf 'FAIL network-renderer-nixos: %s test(s) failed\n' "${failures}" >&2
  exit 1
fi

printf 'PASS network-renderer-nixos: all %s tests passed\n' "${total}"
