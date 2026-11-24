#!/usr/bin/env bash
# GAMP-ID: FS-310-HDS-020-SDS-010-SMS-060
# GAMP-SCOPE: software-module-test
#
# A RENDERED ROUTE'S PLACE MUST BE THE CANONICAL RECORD'S PLACE.
#
# The violation: `canonicalRoutes` carries (target, interface, table, dst,
# gateway, metric) and `policyRoutingAllocation.tableId` per interface, and the
# renderer nevertheless recomputes placement -- `routeOutputInterface` in
# policy-routing/route-helpers.nix, `tableForOutputIfName` in
# policy-routing/aggregate.nix -- then appends the model's own records and deletes
# the collisions with `dropDerivedCopies`. That heuristic keys on all five parts,
# so a derived route that agrees on dst, gateway and metric but disagrees on TABLE
# is not treated as a duplicate: it survives beside the canonical record, and one
# model route becomes two target primitives in two tables. Measured on the
# provider-overlay example: 97 canonical records become 363 rendered routes.
#
# WHAT THIS PROVES
# ----------------
#   CASE 1  same (interface, dst, gateway, metric), different table: the render
#           throws, naming the row, the five-part identity and both places. This
#           is the seed for the exact disagreement the live example produces.
#   CASE 2  same five parts, one place: no throw. Without this, CASE 1 would be
#           satisfied by a check that throws on any two routes.
#   CASE 3  a route that differs in dst/gateway/metric is a DIFFERENT route and is
#           not a placement disagreement: no throw. The comparison is on identity,
#           not on "two routes exist".
#   CASE 4  wiring: the renderer boundary calls the check. A check nothing calls
#           proves nothing about the render.
#
# Evidence boundary: construction. Evaluation of the placement module with seeded
# route records, plus one source read. No build, no lab.
set -euo pipefail

repo_root="${SMS_TEST_REPO_ROOT:-$(git -C "$(dirname "${BASH_SOURCE[0]}")" rev-parse --show-toplevel)}"
trace_id="FS-310-HDS-020-SDS-010-SMS-060"
module="${repo_root}/s88/ControlModule/render/container-networks/placement-agreement.nix"
boundary="${repo_root}/s88/ControlModule/render/container-networks/interface-units.nix"

echo "--- PLACEMENT-AGREEMENT: a recomputed route table crashes the render ---"
echo ""

[[ -f "${module}" ]] || {
  echo "FAIL PLACEMENT-AGREEMENT: no ${module}" >&2
  exit 1
}

issues=0

# $1 = json of {canonicalRoutes, derivedRoutes}. Prints "true" or the throw text.
eval_case() {
  local payload="$1"
  PAYLOAD="${payload}" REPO="${repo_root}" \
    nix eval --impure --json --expr '
      let
        repoRoot = builtins.getEnv "REPO";
        flake = builtins.getFlake ("path:" + repoRoot);
        lib = flake.inputs.nixpkgs.lib;
        module = import (repoRoot + "/s88/ControlModule/render/container-networks/placement-agreement.nix") { inherit lib; };
        payload = builtins.fromJSON (builtins.getEnv "PAYLOAD");
      in
      module.assertAgrees {
        ifName = "uplink0";
        inherit (payload) canonicalRoutes derivedRoutes;
      }' 2>&1 || true
}

# The canonical record the model publishes for this interface.
canonical_record='{"Destination":"0.0.0.0/0","Table":1001,"Gateway":"192.0.2.1","Metric":50}'

# ---------------------------------------------------------------------------
# CASE 1 -- the renderer recomputed the table. Same route, two places.
# ---------------------------------------------------------------------------
mismatch_payload='{"canonicalRoutes":['"${canonical_record}"'],"derivedRoutes":[{"Destination":"0.0.0.0/0","Table":1002,"Gateway":"192.0.2.1","Metric":50}]}'
mismatch_out="$(eval_case "${mismatch_payload}")"

if ! grep -qF "${trace_id}" <<<"${mismatch_out}"; then
  issues=$((issues + 1))
  {
    echo "FAIL CASE 1: a table disagreement did not fail naming ${trace_id}"
    echo "  got: ${mismatch_out}"
  } >&2
elif ! grep -qF "0.0.0.0/0" <<<"${mismatch_out}" || ! grep -qF "192.0.2.1" <<<"${mismatch_out}"; then
  issues=$((issues + 1))
  {
    echo "FAIL CASE 1: the failure does not name the five-part route identity"
    echo "  got: ${mismatch_out}"
  } >&2
elif ! grep -qF "1001" <<<"${mismatch_out}" || ! grep -qF "1002" <<<"${mismatch_out}"; then
  issues=$((issues + 1))
  {
    echo "FAIL CASE 1: the failure does not name both places (canonical and rendered table)"
    echo "  got: ${mismatch_out}"
  } >&2
elif grep -qx 'true' <<<"${mismatch_out}"; then
  issues=$((issues + 1))
  {
    echo "FAIL CASE 1: the renderer recomputed the table and the render still succeeded"
    echo "  got: ${mismatch_out}"
  } >&2
else
  echo "PASS CASE 1: a recomputed table crashes the render, naming the row, the five-part identity and both places"
fi

# ---------------------------------------------------------------------------
# CASE 2 -- agreement on all five parts is not a disagreement.
# ---------------------------------------------------------------------------
agree_payload='{"canonicalRoutes":['"${canonical_record}"'],"derivedRoutes":['"${canonical_record}"']}'
agree_out="$(eval_case "${agree_payload}")"
if [[ "${agree_out}" != "true" ]]; then
  issues=$((issues + 1))
  {
    echo "FAIL CASE 2: agreeing places were reported as a disagreement"
    echo "  got: ${agree_out}"
  } >&2
else
  echo "PASS CASE 2: the same five parts in the same table pass (the check can pass)"
fi

# ---------------------------------------------------------------------------
# CASE 3 -- a different route is not a disagreement, and the seeded negative for
# the identity comparison: only the table may differ for this check to fire.
# ---------------------------------------------------------------------------
other_payload='{"canonicalRoutes":['"${canonical_record}"'],"derivedRoutes":[{"Destination":"198.51.100.0/24","Table":1002,"Gateway":"192.0.2.9","Metric":10}]}'
other_out="$(eval_case "${other_payload}")"
if [[ "${other_out}" != "true" ]]; then
  issues=$((issues + 1))
  {
    echo "FAIL CASE 3: two different routes were reported as a placement disagreement"
    echo "  got: ${other_out}"
  } >&2
else
  echo "PASS CASE 3: a route with a different dst/gateway/metric is not a placement disagreement"
fi

# ---------------------------------------------------------------------------
# CASE 4 -- wiring: the renderer boundary must call the check, or CASE 1..3 are
# evidence about a module nothing uses.
# ---------------------------------------------------------------------------
if [[ ! -f "${boundary}" ]] || ! grep -q "placementAgreement.assertAgrees" "${boundary}"; then
  issues=$((issues + 1))
  {
    echo "FAIL CASE 4: ${boundary} does not call placementAgreement.assertAgrees"
    echo "  the check exists but the render does not run it"
  } >&2
else
  echo "PASS CASE 4: the interface-unit render calls the placement check"
fi

echo ""
if ((issues > 0)); then
  echo "FAIL PLACEMENT-AGREEMENT: ${issues} issue(s)." >&2
  echo "  The check is ${module}, called from ${boundary}." >&2
  echo "  The fix is to stop recomputing placement and install the canonical record's" >&2
  echo "  table; that is a separate change." >&2
  exit 1
fi

echo "PASS PLACEMENT-AGREEMENT: a rendered route whose place disagrees with the canonical record crashes the render"
exit 0
