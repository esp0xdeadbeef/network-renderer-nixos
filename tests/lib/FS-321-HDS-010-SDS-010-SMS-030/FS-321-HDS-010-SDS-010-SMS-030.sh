#!/usr/bin/env bash
# GAMP-ID: FS-321-HDS-010-SDS-010-SMS-030
# GAMP-SCOPE: software-module-test
#
# SPEC:   GAMP/SMS/FS-321-HDS-010-SDS-010-SMS-030.md
# OWNER:  network-renderer-nixos
# MODULE: Thin Host Configuration
#
# THIS TEST IS EXPECTED TO FAIL until the module exists and is enforced.
# Do not weaken the test to make it pass — implement the module.
#
# Predicates taken from the SMS:
#   P1  Host configuration is limited to environment selection, host management
#       reachability, and renderer-output import.
#   P2  Generated network behavior emitted into host configuration is rejected.
#   P3  Route, firewall, DNS, NAT/NAT66, overlay, policy and forwarding semantics
#       stay with the owning renderer or an upstream model contract.
#   P4  Every host-configuration entry is attributed to one of the three
#       permitted classes, and an unattributable entry is refused.
#
# Seeded negatives the SMS requires:
#   SN1  A generated route placed into host configuration is rejected.
#   SN2  A firewall policy placed into host configuration is rejected.
#   SN3  A host entry fitting none of the three permitted classes is rejected.
#   SN4  Environment selection, management reachability and output import alone
#        are accepted.
#
# To implement: add the host-boundary classification over the emitted host
# configuration and the three refusals above.
set -euo pipefail

repo_root="${SMS_TEST_REPO_ROOT:-$(git -C "$(dirname "${BASH_SOURCE[0]}")" rev-parse --show-toplevel)}"
source "${repo_root}/tests/lib/direct-test-guard.sh"

fail() { echo "FAIL thin-host-configuration: $*" >&2; exit 1; }

search_roots=("${repo_root}/s88" "${repo_root}/lib")

# P4: the three permitted classes must be expressible before an entry can be
# attributed to them.
missing=""
grep -rqiE 'environment.?selection|environmentClass' "${search_roots[@]}" --include=*.nix 2>/dev/null || missing="${missing} environment-selection"
grep -rqiE 'management.?(reachability|access)' "${search_roots[@]}" --include=*.nix 2>/dev/null || missing="${missing} management-reachability"
grep -rqiE 'renderer.?output|output.?import' "${search_roots[@]}" --include=*.nix 2>/dev/null || missing="${missing} renderer-output-import"
if [[ -n "${missing}" ]]; then
  fail "P4 the host-configuration boundary does not express:${missing}"
fi

# P2/SN1/SN2: generated behavior in host configuration must be refused.
if ! grep -rqiE 'generated.?behavior|generatedBehavior|host.?boundary' "${search_roots[@]}" --include=*.nix 2>/dev/null; then
  fail "SN1/SN2 no refusal exists for generated network behavior placed in host configuration"
fi

# P3: routing/firewall/DNS/NAT semantics must be attributed away from the host.
if ! grep -rqiE 'owning.?(renderer|layer)|owner' "${search_roots[@]}" --include=*.nix 2>/dev/null; then
  fail "P3 no owning-layer attribution exists for network semantics, so they cannot be refused in host configuration"
fi

# SN3: an unattributable host entry must be refused.
if ! grep -rqiE 'unattributable|unclassified.?(entry|host)' "${search_roots[@]}" --include=*.nix 2>/dev/null; then
  fail "SN3 no refusal exists for a host entry that fits none of the three permitted classes"
fi

echo "PASS thin-host-configuration"
