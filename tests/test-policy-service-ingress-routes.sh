#!/usr/bin/env bash
# GAMP-ID: FS-270-HDS-010-SDS-010-SMS-020
# GAMP-SCOPE: software-integration-test
#
# SPEC:   GAMP/SMS/FS-270-HDS-010-SDS-010-SMS-020.md (Client Tenant Policy Transit)
# SPEC:   GAMP/SMS/FS-322-HDS-010-SDS-010-SMS-020.md (Scope Selection Resolution)
# OWNER:  network-renderer-nixos (this case), network-control-plane-model (the gap)
#
# EXPECTED TO FAIL until the upstream fact exists. This is NOT a renderer bug, and
# it must not be made to pass by teaching the renderer to work it out.
#
# What the case asserts: an access-to-access service relation returns through the
# same policy-state owner as its forward request, so the policy table selected for
# the DMZ source carries the DMZ prefix. It currently does not: a rule admits
# `From 10.90.10.0/24` into table 1003 while 1003 carries only the source's own
# access unit, so the packet falls through to main.
#
# Why the renderer cannot fix it:
#   - URS: reachability and permission "shall not be conflated". Deriving the
#     return leg from the relation record is exactly that conflation. It was
#     implemented, measured and reverted; it also regressed an FS-540 assertion
#     that the client east-west table must not reach the management prefix.
#   - URS: a fact that follows deterministically from other modeled facts "shall
#     be derived by the owning layer".
#
# Where the fact belongs: a scope's reachability is its offers plus its selects,
# joined by network-control-plane-model onto the runtime target as
# `effectiveRuntimeRealization.resolvedReachability`
# (FS-322-HDS-010-SDS-010-SMS-020, "Per-scope resolved reachability"). Before that
# fact existed, every runtime target exposed only interfaces, loopback and
# targetOriginatedSelection. network-realization-model cannot add it either: it
# fails with NR_REALIZATION_INVENTED_SEMANTIC unless its network data equals CPM
# verbatim.
#
# Once resolvedReachability is present, this case should be satisfied by consuming
# it, not by inferring anything from relations.
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${repo_root}/tests/lib/test-common.sh"

example_root="${repo_root}/tests/fixtures/s-router-overlay-dns-lane-policy"
result_json="$(mktemp)"
eval_stderr="$(mktemp)"
trap 'rm -f "${result_json}" "${eval_stderr}"' EXIT

nix_eval_json_or_fail \
  policy-service-ingress-routes \
  "${result_json}" \
  "${eval_stderr}" \
  env REPO_ROOT="${repo_root}" \
    INTENT_PATH="${example_root}/intent.nix" \
    INVENTORY_PATH="${example_root}/inventory-nixos.nix" \
    nix eval \
      --extra-experimental-features 'nix-command flakes' \
      --impure --json \
      --file "${repo_root}/tests/nix/policy-service-ingress-routes.nix"

if ! assert_json_checks_ok policy-service-ingress-routes "${result_json}"; then
  jq -S . "${result_json}" >&2 || true
  exit 1
fi

echo "PASS policy-service-ingress-routes"
