#!/usr/bin/env bash
# run-all-tests.sh — Run all NixOS renderer tests asynchronously.
#
# Usage:
#   bash run-all-tests.sh
#
# Auto-discovers every test entrypoint through the shared
# scripts/lib/discover-tests.sh contract, runs them in parallel, reports
# PASS/FAIL per test, and exits non-zero if any test fails.
#
# Environment:
#   TEST_JOBS              Max concurrent tests (default: nproc)
#   TEST_TIMEOUT_SECONDS    Per-test timeout (default: 1800)
#   TEST_FAIL_FAST          Stop at the first failure (default: on locally, off in CI)
#
# FAIL FAST, AND WHY IT IS NOT THE CI DEFAULT
# -------------------------------------------
# Iterating on a bug means running this suite dozens of times, and the full sweep is
# ~20 minutes. Waiting for every test when the first one already failed buys nothing:
# the remaining results are about defects nobody is going to fix until that one is.
# So fail-fast defaults ON when a human is driving.
#
# CI is the opposite question. A CI run answers "is the branch good", and its value is
# the COMPLETE list of what is broken -- one red per run means as many runs as defects.
# Fail-fast therefore defaults OFF when CI is detected (the CI environment variable
# that every hosted runner sets), and an explicit TEST_FAIL_FAST always wins. The
# default is reported at startup so a run's behaviour is never a guess.

set -euo pipefail
exec > >(tee "${TMPDIR:-/var/tmp}/network-renderer-nixos-tests.out")

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

if [[ -n "${TEST_FAIL_FAST:-}" ]]; then
  fail_fast="${TEST_FAIL_FAST}"
  fail_fast_origin="TEST_FAIL_FAST"
elif [[ -n "${CI:-}" ]]; then
  fail_fast="0"
  fail_fast_origin="CI detected"
else
  fail_fast="1"
  fail_fast_origin="local default"
fi
case "${fail_fast}" in
  0|1) ;;
  *) echo "error: TEST_FAIL_FAST must be 0 or 1, got '${fail_fast}'" >&2; exit 2 ;;
esac

# --- discover tests ---
# shellcheck source=scripts/lib/discover-tests.sh
source "${repo_root}/scripts/lib/discover-tests.sh"
mapfile -t test_names < <(discover_tests "${repo_root}")

test_files=()
for test_name in "${test_names[@]}"; do
  test_files+=("${test_dir}/${test_name}")
done

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
skipped=0

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

  if (( status == 0 )) && grep -q '^SKIP ' "${log_file}"; then
    # A case that cannot run in this environment (no adjacent checkout, no CLAB
    # path) states SKIP and exits 0. It is not a pass: count it separately so a
    # CI run cannot claim coverage it did not have.
    printf 'SKIP %s (%ss)\n' "${name}" "${elapsed}"
    grep '^SKIP ' "${log_file}" >&2 || true
    skipped=$((skipped + 1))
  elif (( status == 0 )); then
    printf 'PASS %s (%ss)\n' "${name}" "${elapsed}"
    passed=$((passed + 1))
  else
    printf 'FAIL %s (exit %s, %ss)\n' "${name}" "${status}" "${elapsed}" >&2
    awk -v prefix="[${name}] " '{ print prefix $0 }' "${log_file}" >&2
    failures=$((failures + 1))
  fi
}

printf 'running %s tests with TEST_JOBS=%s, fail-fast=%s (%s)\n' \
  "${#test_files[@]}" "${jobs}" "${fail_fast}" "${fail_fast_origin}"

# Every started pid, so a fail-fast stop can cancel work that is still running
# instead of waiting out the slow tests it already knows it does not want.
declare -a started_pids=()

for test_file in "${test_files[@]}"; do
  if (( fail_fast == 1 && failures > 0 )); then
    printf 'STOP fail-fast: not starting remaining tests after %s failure(s)\n' "${failures}" >&2
    # Cancel what is still in flight. Waiting for it would delay the answer we
    # already have -- and a long test still running is exactly the case fail-fast
    # exists to avoid.
    for pid in "${started_pids[@]}"; do
      kill -TERM "${pid}" 2>/dev/null || true
    done
    break
  fi
  name="${test_file#${repo_root}/}"
  log_file="${tmp_dir}/${name//\//__}.log"
  printf 'START %s\n' "${name}"

  (
    timeout "${test_timeout_seconds}" bash -c '
      _source="$1"
      _test="$2"
      case "${_test}" in *.py) ;; *) source "$_source";; esac
      # The trace id the case derives for itself, from the file name.
      _trace="$(basename "${_test}" .sh)"
      case "${_test}" in
        *.py) set --; exec python3 "$_test" ;;
        # Pass the trace id as $1. These cases take `trace_id="${1:-${invoked_name}}"`
        # where `invoked_name` is `basename "$0"`, and while `source`d `$0` is THIS
        # runner, so the fallback yielded "run-all-tests" and every case exited 2:
        #   usage: run-all-tests <trace-id>
        # 81 of 110 cases were reported as failures for that reason alone. Running
        # any one of them directly passed, which is what gave it away.
        *)    set -- "${_trace}"; source "$_test" ;;
      esac
    ' _ "${repo_root}/tests/lib/test-common.sh" "${test_file}"
  ) >"${log_file}" 2>&1 &

  started_pids+=("$!")
  pid_to_name[$!]="${name}"
  pid_to_log[$!]="${log_file}"
  pid_to_start[$!]="${SECONDS}"
  running=$((running + 1))

  if (( running >= jobs )); then
    wait_for_one
  fi
done

# Reap the cancelled jobs. Their own result is meaningless once cancelled, so they
# are neither counted as a pass nor as an extra failure.
while (( running > 0 )); do
  finished_pid=""
  wait -n -p finished_pid 2>/dev/null || true
  if [[ -n "${finished_pid}" && -n "${pid_to_name[${finished_pid}]:-}" ]]; then
    unset "pid_to_name[${finished_pid}]"
    unset "pid_to_log[${finished_pid}]"
    unset "pid_to_start[${finished_pid}]"
    running=$((running - 1))
  else
    running=0
  fi
done

if (( fail_fast == 1 && failures > 0 )); then
  not_run=$(( ${#test_files[@]} - passed - skipped - failures ))
  if (( not_run > 0 )); then
    printf 'NOT RUN %s test(s): fail-fast stopped the sweep after the first failure\n' "${not_run}" >&2
  fi
fi

# --- report ---
total=$((passed + skipped + failures))
printf '\n%s passed, %s skipped, %s failed of %s tests\n' "${passed}" "${skipped}" "${failures}" "${total}"
printf 'PASS: %s, SKIP: %s, FAIL: %s, TOTAL: %s\n' "${passed}" "${skipped}" "${failures}" "${total}" >&2

if (( failures > 0 )); then
  printf 'FAIL network-renderer-nixos: %s test(s) failed\n' "${failures}" >&2
  exit 1
fi

if (( skipped > 0 )); then
  printf 'PASS network-renderer-nixos: %s passed, %s skipped (not run)\n' "${passed}" "${skipped}"
else
  printf 'PASS network-renderer-nixos: all %s tests passed\n' "${total}"
fi
