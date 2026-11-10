#!/usr/bin/env bash
# GAMP-ID: FS-625-HDS-010-SDS-010-SMS-020
# GAMP-SCOPE: software-module-test
#
# SPEC:   GAMP/SMS/FS-625-HDS-010-SDS-010-SMS-020.md
# OWNER:  network-renderer-nixos
# MODULE: Mapping-Relationship Limits
#
# EXPECTED TO FAIL. No port-mapping implementation exists in any of the eight
# implementation repositories, so this case encodes the SMS contract and reports
# the gap. Do not weaken it to pass — implement the module.
#
# Predicates taken from the SMS:
#   P1  Requester scope, mapping range, lifetime, audit behavior, conflict
#       handling and public exposure limits are all required.
#   P2  No limit is defaulted.
#   P3  A granted mapping is bounded to its declared range, lifetime and ports.
#
# Seeded negatives the SMS requires:
#   SN1-SN6  each of the six limits omitted in turn is refused naming it.
#   SN7  A defaulted limit is refused.
#   SN8  An over-grant beyond the declared bounds is refused.
#
# To implement: renderer-emitted port-mapping service state, gated on a modeled
# relationship that names requester scope, allowed mapping range, lifetime, audit
# behavior, conflict handling and public exposure limits.
set -euo pipefail

repo_root="${SMS_TEST_REPO_ROOT:-$(git -C "$(dirname "${BASH_SOURCE[0]}")" rev-parse --show-toplevel)}"
source "${repo_root}/tests/lib/direct-test-guard.sh"

fail() { echo "FAIL mapping-relationship-limits: $*" >&2; exit 1; }

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

echo "PASS mapping-relationship-limits"
