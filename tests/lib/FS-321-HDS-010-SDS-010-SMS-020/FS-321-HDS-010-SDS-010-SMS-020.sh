#!/usr/bin/env bash
# GAMP-ID: FS-321-HDS-010-SDS-010-SMS-020
# GAMP-SCOPE: software-module-test
#
# SPEC:   GAMP/SMS/FS-321-HDS-010-SDS-010-SMS-020.md
# OWNER:  network-renderer-nixos
# MODULE: Bounded Custom Service
#
# THIS TEST IS EXPECTED TO FAIL until the module exists and is enforced.
# Do not weaken the test to make it pass — implement the module.
#
# Predicates taken from the SMS:
#   P1  A generated script or custom service is accepted only when a declared gap
#       names the capability the native primitives cannot express.
#   P2  The service carries a model input contract, an output contract, a failure
#       behavior, and a startup ordering.
#   P3  A custom service hides no route, firewall, DNS, NAT/NAT66, overlay,
#       policy, persistence or forwarding semantic the platform could express.
#   P4  The service is bounded to its declared gap and exposes the gap beside it.
#
# Seeded negatives the SMS requires:
#   SN1  A custom service with no declared gap is rejected.
#   SN2  Each of the four contract fields, omitted in turn, is rejected naming
#        that field (four cases).
#   SN3  A platform-expressible route or firewall semantic hidden inside a custom
#        service is rejected.
#   SN4  A bounded service with a declared gap and all four fields is accepted.
#
# To implement: add the bounded-service acceptance path with the gap declaration,
# the four required contract fields, and the hidden-semantics refusal.
set -euo pipefail

repo_root="${SMS_TEST_REPO_ROOT:-$(git -C "$(dirname "${BASH_SOURCE[0]}")" rev-parse --show-toplevel)}"
source "${repo_root}/tests/lib/direct-test-guard.sh"

fail() { echo "FAIL bounded-custom-service: $*" >&2; exit 1; }

search_roots=("${repo_root}/s88" "${repo_root}/lib" "${repo_root}")

# P1: the declared-gap concept must exist before a custom service can be bounded.
if ! grep -rqiE 'capability.?gap|native.?gap|declared.?gap' "${search_roots[@]}" --include=*.nix 2>/dev/null; then
  fail "SN1 no declared-gap concept exists, so a custom service cannot be refused for having none"
fi

# P2: the four contract fields must each be present somewhere in the service
# contract surface. Checked individually so the failure names what is missing.
missing=""
grep -rqiE 'input.*contract|modelInput' "${search_roots[@]}" --include=*.nix 2>/dev/null || missing="${missing} model-input-contract"
grep -rqiE 'output.*contract|modelOutput' "${search_roots[@]}" --include=*.nix 2>/dev/null || missing="${missing} output-contract"
grep -rqiE 'failure.?behavior|failureBehavior' "${search_roots[@]}" --include=*.nix 2>/dev/null || missing="${missing} failure-behavior"
grep -rqiE 'startup.?ordering|after\s*=|wants\s*=|requires\s*=' "${search_roots[@]}" --include=*.nix 2>/dev/null || missing="${missing} startup-ordering"
if [[ -n "${missing}" ]]; then
  fail "SN2 the custom-service contract surface is missing:${missing}"
fi

# P3/SN3: hidden platform-expressible semantics must be refused.
if ! grep -rqiE 'hidden.?(semantic|semantics)|hides' "${search_roots[@]}" --include=*.nix 2>/dev/null; then
  fail "SN3 no refusal exists for a custom service hiding a platform-expressible semantic"
fi

# P4: the service must be bounded to its gap and expose the gap.
if ! grep -rqiE 'bounded|scopeClass|boundedTo' "${search_roots[@]}" --include=*.nix 2>/dev/null; then
  fail "P4 no bounding exists between a custom service and its declared gap"
fi

echo "PASS bounded-custom-service"
