#!/usr/bin/env bash
# GAMP-ID: FS-982-HDS-010-SDS-010-SMS-110
# GAMP-SCOPE: software-module-test
# FS-982-SMS-110-RUNTIME: scoped-artifact
# FS-982-SMS-110-ARTIFACT: NixOS renderer explicit-role module artifact
# FS-982-SMS-110-EVIDENCE: tests/test-fs320-hds040-sds010-sms060-explicit-role-classification.sh
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

fail() {
  echo "FAIL fs982-sms110-nixos-smt: $*" >&2
  exit 1
}

evidence="tests/test-fs320-hds040-sds010-sms060-explicit-role-classification.sh"
output="$(NETWORK_REPO_DIRECT_TEST_OK=1 bash "${repo_root}/${evidence}" 2>&1)" || {
  printf '%s\n' "${output}" >&2
  fail "${evidence} failed"
}

grep -Fq "PASS: FS-320-HDS-040-SDS-010-SMS-060" <<<"${output}" \
  || fail "${evidence} did not emit the explicit role classification PASS marker"
grep -Fq "sourceKind" <<<"${output}" \
  || fail "${evidence} did not exercise sourceKind fallback rejection"

echo "PASS fs982-sms110-nixos-smt"
