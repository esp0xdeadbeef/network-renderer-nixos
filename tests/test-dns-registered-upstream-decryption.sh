#!/usr/bin/env bash
# CI entry point for the FS-540-HDS-010-SDS-010-SMS-035 registered-upstream
# decryption case.
#
# The SMS case lives under tests/lib/<trace-id>/ where the GAMP runner expects
# it, but run-all-tests.sh only discovers tests/test-*.sh, so that directory was
# unreachable from CI. This case is construction-scope: it generates its own age
# identities, needs no live host, and must run on the runner.
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
trace_id="FS-540-HDS-010-SDS-010-SMS-035"
case_test="${repo_root}/tests/lib/${trace_id}/test-${trace_id}-registered-upstream-decryption.sh"

if [[ ! -f "${case_test}" ]]; then
  echo "FAIL ${trace_id}: case not found at ${case_test}" >&2
  exit 1
fi

SMS_TEST_REPO_ROOT="${repo_root}" SMS_TEST_TRACE_ID="${trace_id}" exec bash "${case_test}"
