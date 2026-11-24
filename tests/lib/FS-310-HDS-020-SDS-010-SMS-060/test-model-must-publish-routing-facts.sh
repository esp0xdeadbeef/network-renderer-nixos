#!/usr/bin/env bash
# GAMP-ID: FS-310-HDS-020-SDS-010-SMS-060
# GAMP-SCOPE: software-module-test
#
# THE RENDERER MAY NOT AUTHOR FACTS THE MODEL DOES NOT PUBLISH.
#
# `policyRoutingSources` (which interfaces feed which policy table) and
# `networkBehavior` (the class flags that make a unit a selector, a policy
# target, an upstream selector or an access gateway) are facts about the
# network. `network-control-plane-model/src` has ZERO occurrences of either
# name, so the model does not publish them; two renderer projections author them
# instead, from interface topology:
#
#   s88/Unit/mapping/runtime-targets/interfaces/policy-routing-sources.nix
#   s88/Unit/mapping/runtime-targets/interfaces/network-behavior.nix
#
# FS-310-HDS-020-SDS-010-SMS-060 forbids exactly that: "The renderer shall not
# choose, infer, or withhold a route's table or lane occurrence: it shall not
# gate a route's materialization on the presence of a forwarding rule, derive
# occurrence from interface topology, or rely on an environment-supplied
# fallback table."
#
# WHAT THIS PROVES
# ----------------
#   CASE 1  a runtime target the model describes WITHOUT those two fields makes
#           the mapping throw, naming the field, the target and the row.
#   CASE 2  the same target WITH the fields maps cleanly. Without this, CASE 1
#           would be satisfied by a mapping that never evaluates.
#
# It does not assert what the mapped value IS when the model does supply it: the
# derivation files still overwrite the model's field, and removing them is the
# fix, a separate change. This case is the enforcement that the model has to
# publish the fact at all.
#
# Evidence boundary: construction. Evaluation of the mapping entrypoint with a
# synthetic CPM. No build, no lab.
set -euo pipefail

repo_root="${SMS_TEST_REPO_ROOT:-$(git -C "$(dirname "${BASH_SOURCE[0]}")" rev-parse --show-toplevel)}"
trace_id="FS-310-HDS-020-SDS-010-SMS-060"

echo "--- MODEL-MUST-PUBLISH-ROUTING-FACTS: a missing routing fact crashes the mapping ---"
echo ""

issues=0

map_target() {
  local mode="$1"
  MODE="${mode}" REPO="${repo_root}" \
    nix eval --impure --json --expr '
      let
        repoRoot = builtins.getEnv "REPO";
        flake = builtins.getFlake ("path:" + repoRoot);
        lib = flake.inputs.nixpkgs.lib;
        mapping = import (repoRoot + "/s88/Unit/mapping/runtime-targets.nix") { inherit lib; };
        mode = builtins.getEnv "MODE";
        published =
          if mode == "with" then {
            policyRoutingSources = { uplink = [ "uplink-testnet" ]; };
            networkBehavior = {
              isSelector = false;
              isUpstreamSelector = false;
              isPolicy = true;
              isAccessGateway = false;
              keepInterfaceRoutesInMain = false;
            };
          }
          else { };
        target = {
          logicalNode.name = "target-uplink";
          role = "access";
          interfaces = { };
          effectiveRuntimeRealization.interfaces = { };
        } // published;
        cpm = {
          data.enterprise.site.site1.runtimeTargets."target-uplink" = target;
        };
        mapped = mapping.normalizedRuntimeTargets {
          inherit cpm;
          file = "tests/lib/FS-310-HDS-020-SDS-010-SMS-060/test-model-must-publish-routing-facts.sh";
        };
      in
      # The values are forced, not only the attribute names: an attribute is
      # lazy, so a render that never reads the fact would never run the check.
      builtins.deepSeq (builtins.attrValues mapped) (builtins.attrNames mapped)' 2>&1 || true
}

# ---------------------------------------------------------------------------
# CASE 1 -- the model publishes neither field: the mapping must throw, naming
# the field, the target and the row.
# ---------------------------------------------------------------------------
without_out="$(map_target without)"

if ! grep -qF "${trace_id}" <<<"${without_out}"; then
  issues=$((issues + 1))
  {
    echo "FAIL CASE 1: a target without the routing facts did not fail naming ${trace_id}"
    echo "  got: ${without_out}"
  } >&2
elif ! grep -qE "policyRoutingSources|networkBehavior" <<<"${without_out}"; then
  issues=$((issues + 1))
  {
    echo "FAIL CASE 1: the failure does not name the field the model must publish"
    echo "  got: ${without_out}"
  } >&2
elif ! grep -qF "target-uplink" <<<"${without_out}"; then
  issues=$((issues + 1))
  {
    echo "FAIL CASE 1: the failure does not name the target"
    echo "  got: ${without_out}"
  } >&2
elif grep -qx '\[[^]]*\]' <<<"${without_out}"; then
  issues=$((issues + 1))
  {
    echo "FAIL CASE 1: the mapping SUCCEEDED and derived the facts from topology -- that is the violation"
    echo "  got: ${without_out}"
  } >&2
else
  echo "PASS CASE 1: a target the model does not describe fails the mapping, naming the field, the target and the row"
fi

# ---------------------------------------------------------------------------
# CASE 2 -- the seeded negative: the same target with the fields published maps
# cleanly, so CASE 1 is not a mapping that always throws.
# ---------------------------------------------------------------------------
with_out="$(map_target with)"

if ! grep -qF 'target-uplink' <<<"${with_out}"; then
  issues=$((issues + 1))
  {
    echo "FAIL CASE 2: with the model's fields published the mapping still failed"
    echo "  got: ${with_out}"
  } >&2
else
  echo "PASS CASE 2: with the model's fields published the same target maps (the check can pass)"
fi

echo ""
if ((issues > 0)); then
  echo "FAIL MODEL-MUST-PUBLISH-ROUTING-FACTS: ${issues} issue(s)." >&2
  echo "  The check is s88/Unit/mapping/runtime-targets/default.nix (requireModelFact) and" >&2
  echo "  s88/ControlModule/mapping/container-runtime/model/container-assembly.nix." >&2
  echo "  The fix is the model publishing the field, then deleting the derivation." >&2
  exit 1
fi

echo "PASS MODEL-MUST-PUBLISH-ROUTING-FACTS: a routing fact the model does not publish crashes the mapping"
exit 0
