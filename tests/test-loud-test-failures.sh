#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${repo_root}/tests/lib/test-common.sh"

violations="$(
  rg -n '\|\s*grep\s+-qx\s+true' "${repo_root}/tests" -g '*.sh' || true
)"

if [[ -n "$violations" ]]; then
  echo "FAIL loud-test-failures: tests must not hide nix eval failures behind grep -qx true" >&2
  echo "$violations" >&2
  echo "Use nix_eval_json_or_fail plus assert_json_checks_ok with named checks instead." >&2
  exit 1
fi

pass loud-test-failures
