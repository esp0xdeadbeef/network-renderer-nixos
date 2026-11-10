#!/usr/bin/env bash
# GAMP-ID: FS-321-HDS-010-SDS-010-SMS-010
# GAMP-SCOPE: software-module-test
#
# SPEC:   GAMP/SMS/FS-321-HDS-010-SDS-010-SMS-010.md
# OWNER:  network-renderer-nixos
# MODULE: Native-Mechanism Preference
#
# THIS TEST IS EXPECTED TO FAIL until the module exists and is enforced.
# Do not weaken the test to make it pass — implement the module.
#
# Predicates taken from the SMS:
#   P1  Addresses, routes, links, firewall rules, DNS records, routing protocol
#       configuration, overlays, services, secrets and persistence are emitted
#       through the platform's own configuration surface.
#   P2  An opaque payload, an alternate operating system, or a broad imperative
#       rewrite in place of platform configuration is rejected.
#   P3  A custom mechanism that duplicates an available native capability is
#       rejected.
#   P4  Every realized behavior carries the native mechanism that carries it.
#
# Seeded negatives the SMS requires:
#   SN1  A route emitted as an opaque script payload is rejected.
#   SN2  A firewall policy emitted as a broad imperative rewrite is rejected.
#   SN3  A native capability duplicated by a custom mechanism is rejected.
#   SN4  The same behavior emitted natively is accepted with attribution.
#
# To implement: add the preference pass that classifies each emitted behavior as
# native / bounded-custom / host, attributes the native mechanism, and refuses the
# three negations above.
set -euo pipefail

repo_root="${SMS_TEST_REPO_ROOT:-$(git -C "$(dirname "${BASH_SOURCE[0]}")" rev-parse --show-toplevel)}"
source "${repo_root}/tests/lib/direct-test-guard.sh"

fail() { echo "FAIL native-mechanism-preference: $*" >&2; exit 1; }

# P1: the renderer must actually use platform-native surfaces.
native_hits=0
for surface in 'networking\.' 'systemd\.network' 'networking\.firewall' 'networking\.nftables' 'services\.' 'environment\.etc'; do
  grep -rqE "${surface}" "${repo_root}" --include=*.nix 2>/dev/null && native_hits=$((native_hits + 1))
done
if ((native_hits < 3)); then
  fail "P1 the renderer does not emit platform-native configuration surfaces (found ${native_hits}/6)"
fi

# P2: an alternate operating system in place of platform configuration must be
# refused. Detect the capability first; there is nothing to enforce without it.
if ! grep -rqiE 'alternate.?os|opaque.?(payload|blob)|imperative.?rewrite' \
  "${repo_root}/s88" "${repo_root}/lib" --include=*.nix 2>/dev/null; then
  fail "SN1/SN2 no rejection exists for an opaque payload, an alternate OS, or a broad imperative rewrite"
fi

# P3: custom-mechanism duplication must be refused.
if ! grep -rqiE 'duplicat' "${repo_root}/s88" "${repo_root}/lib" --include=*.nix 2>/dev/null; then
  fail "SN3 no rejection exists for a custom mechanism duplicating a native capability"
fi

# P4: every realized behavior must carry its native mechanism attribution.
if ! grep -rqiE 'mechanism' "${repo_root}/s88" "${repo_root}/lib" --include=*.nix 2>/dev/null; then
  fail "P4 no mechanism attribution exists per realized behavior"
fi

echo "PASS native-mechanism-preference"
