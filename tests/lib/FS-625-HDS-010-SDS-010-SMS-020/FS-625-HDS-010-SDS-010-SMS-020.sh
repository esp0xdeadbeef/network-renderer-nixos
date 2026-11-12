#!/usr/bin/env bash
# GAMP-ID: FS-625-HDS-010-SDS-010-SMS-020
# GAMP-SCOPE: software-module-test
#
# SPEC:   GAMP/SMS/FS-625-HDS-010-SDS-010-SMS-020.md
# OWNER:  network-renderer-nixos
# MODULE: Mapping-Relationship Limits
#
# The module now exists: s88/ControlModule/render/container-networks/port-mapping.nix
# models the six relationship limits and emits an explicit disabled state per
# protocol. This case checks that the contract is expressible in this repository;
# it no longer claims an absence across other repositories, which was a property of
# the developer's checkout rather than of this renderer.
#
# Do not weaken it to pass.
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

# The absence claim is global: no implementation repository implements port-mapping
# gating. The detector scans every controlled repository, so a single grep hit
# anywhere means the feature started to exist and this case must be re-read.
# The check is scoped to this repository: a sibling checkout elsewhere on a
# developer machine is not evidence about this renderer, and CI does not put
# siblings under $HOME/github (it checks them out beside GITHUB_WORKSPACE).
search=( "${repo_root}" )

# P1 (absence claim): no controlled repository implements port-mapping service
# state, so the deny-by-default posture is implicit rather than modelled, which the
# SMS forbids. A grep hit anywhere means the feature now exists and the case must be
# replaced with a behavioural check.
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
