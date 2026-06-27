#!/usr/bin/env bash
# GAMP-ID: FS-982-HDS-010-SDS-010-SMS-110
# GAMP-SCOPE: software-integration-test
# FS-982-SMS-110-RUNTIME: scoped-artifact
# FS-982-SMS-110-ARTIFACT: NixOS renderer mock CPM internet-mode ruleset artifact
# FS-982-SMS-110-EVIDENCE: tests/test-fs380-internet-mode-renderer.sh
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

fail() {
  echo "FAIL fs982-sms110-nixos-sit: $*" >&2
  exit 1
}

evidence="tests/test-fs380-internet-mode-renderer.sh"
output="$(NETWORK_REPO_DIRECT_TEST_OK=1 bash "${repo_root}/${evidence}" 2>&1)" || {
  printf '%s\n' "${output}" >&2
  fail "${evidence} failed"
}

grep -Fq "PASS: IPv4 masquerade covers client prefixes" <<<"${output}" \
  || fail "${evidence} did not assert IPv4 CPM source-prefix materialization"
grep -Fq "PASS: IPv6 NAT66 covers ULA client prefix" <<<"${output}" \
  || fail "${evidence} did not assert IPv6 CPM source-prefix materialization"

echo "PASS fs982-sms110-nixos-sit"
