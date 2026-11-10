#!/usr/bin/env bash
# GAMP-ID: FS-625-HDS-010-SDS-010-SMS-050
# GAMP-SCOPE: software-module-test
#
# SPEC:   GAMP/SMS/FS-625-HDS-010-SDS-010-SMS-050.md
# OWNER:  network-renderer-nixos
# MODULE: Mapping Audit Record
#
# EXPECTED TO FAIL. No port-mapping implementation exists in any of the eight
# implementation repositories, so this case encodes the SMS contract and reports
# the gap. Do not weaken it to pass — implement the module.
#
# Predicates taken from the SMS:
#   P1  One record per mapping request carries scope, range, lifetime, outcome.
#   P2  Records correlate by site, tenant, host and runtime fact set.
#   P3  Records are privacy-classified and carry no plaintext protected value.
#
# Seeded negatives the SMS requires:
#   SN1  A denied attempt still produces a record.
#   SN2  A missing lifetime fails the record shape.
#   SN3  An unclassified protected value is refused.
#
# To implement: renderer-emitted port-mapping service state, gated on a modeled
# relationship that names requester scope, allowed mapping range, lifetime, audit
# behavior, conflict handling and public exposure limits.
set -euo pipefail

repo_root="${SMS_TEST_REPO_ROOT:-$(git -C "$(dirname "${BASH_SOURCE[0]}")" rev-parse --show-toplevel)}"
source "${repo_root}/tests/lib/direct-test-guard.sh"

fail() { echo "FAIL mapping-audit-record: $*" >&2; exit 1; }

search=( "${repo_root}/s88" "${repo_root}/lib" )

# P1: the renderer must emit an explicit port-mapping service state. No service
# enablement means the deny-by-default posture is implicit, which the SMS forbids.
if ! grep -rqiE 'upnp|natpmp|nat-pmp|portMapping|port-mapping' "${search[@]}" --include=*.nix 2>/dev/null; then
  fail "P1 no port-mapping service state is emitted anywhere in the renderer; UPnP IGD, NAT-PMP and PCP are unmodelled rather than explicitly disabled"
fi

# P2: the six limits must be representable before a relationship can be accepted.
missing=""
for field in requesterScope mappingRange lifetime auditBehavior conflictHandling publicExposureLimits; do
  grep -rqiE "${field}|portMappingRange" "${search[@]}" --include=*.nix 2>/dev/null || missing="${missing} ${field}"
done
if [[ -n "${missing}" ]]; then
  fail "P2 the port-mapping relationship model cannot express:${missing}"
fi

echo "PASS mapping-audit-record"
