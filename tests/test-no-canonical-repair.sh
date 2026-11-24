#!/usr/bin/env bash
# GAMP-ID: FS-310-HDS-040-SDS-010-SMS-100
# GAMP-SCOPE: software-module-test
#
# NO REPAIR AT THE RENDERER BOUNDARY.
#
# The violation: `s88/ControlModule/render/containers.nix` (`canonicalCollection`)
# reads a canonical collection from the bundle, and when the bundle does not
# carry it, reaches into the plain control-plane model (`args.cpm.model` /
# `args.cpm.control_plane_model`) and returns the producer's field. That is the
# renderer repairing the loss the realization model made when it filtered the
# producer's collections through the schema's closed `canonicalCollections` list.
# Because the repair exists, a bundle that is missing published facts renders,
# and nothing in the fleet can see the loss.
#
# WHAT THIS PROVES
# ----------------
#   CASE 1  rendering with `canonicalCollections = { }` FAILS. A silent default
#           is the defect; a successful render here is a FAIL.
#   CASE 2  each of the four collections this module maps, dropped on its own,
#           fails and names itself. The throw is not one blanket refusal.
#   CASE 3  the same render with all four collections present SUCCEEDS. Without
#           this, CASE 1 and CASE 2 are satisfied by a module that cannot render
#           at all, and the check would prove nothing.
#
# The renderer is unusable after this change when the bundle carries no canonical
# content. That is the point: the crash is the enforcement, and the repair is a
# separate change in network-realization-schema and network-realization-model.
#
# Evidence boundary: construction. Evaluation of the module entrypoint with a
# synthetic argument set and no models. No build, no lab.
set -euo pipefail

repo_root="${SMS_TEST_REPO_ROOT:-$(git -C "$(dirname "${BASH_SOURCE[0]}")" rev-parse --show-toplevel)}"
trace_id="FS-310-HDS-040-SDS-010-SMS-100"
entry="${repo_root}/s88/ControlModule/render/containers.nix"

echo "--- NO-CANONICAL-REPAIR: a missing canonical collection crashes the render ---"
echo ""

[[ -f "${entry}" ]] || {
  echo "FAIL NO-CANONICAL-REPAIR: no ${entry}" >&2
  exit 1
}

issues=0

# Evaluate the module entrypoint with a canonicalCollections argument and an empty
# model set, so nothing but the boundary check decides the outcome.
render() {
  local collections_json="$1"
  COLLECTIONS="${collections_json}" REPO="${repo_root}" \
    nix eval --impure --json --expr '
      let
        repoRoot = builtins.getEnv "REPO";
        flake = builtins.getFlake ("path:" + repoRoot);
        lib = flake.inputs.nixpkgs.lib;
        collections = builtins.fromJSON (builtins.getEnv "COLLECTIONS");
      in
      builtins.attrNames (import (repoRoot + "/s88/ControlModule/render/containers.nix") {
        inherit lib;
        repoPath = repoRoot;
        models = { };
        canonicalCollections = collections;
      })' 2>&1 || true
}

all_present='{"canonicalRoutes":[],"canonicalSites":{},"canonicalForwarding":{},"canonicalRuntimeTargets":{}}'

# ---------------------------------------------------------------------------
# CASE 1 -- an empty bundle must not render.
# ---------------------------------------------------------------------------
empty_out="$(render '{}')"
if ! grep -qF "${trace_id}" <<<"${empty_out}"; then
  issues=$((issues + 1))
  {
    echo "FAIL CASE 1: rendering with canonicalCollections = { } did not fail naming ${trace_id}"
    echo "  got: ${empty_out}"
  } >&2
elif ! grep -qiE "canonicalRoutes|canonicalSites|canonicalForwarding|canonicalRuntimeTargets" <<<"${empty_out}"; then
  issues=$((issues + 1))
  {
    echo "FAIL CASE 1: the failure does not name the missing collection"
    echo "  got: ${empty_out}"
  } >&2
elif grep -qx '\[\]' <<<"${empty_out}"; then
  issues=$((issues + 1))
  {
    echo "FAIL CASE 1: the render SUCCEEDED with an empty canonical bundle -- a silent default is the defect"
    echo "  got: ${empty_out}"
  } >&2
else
  echo "PASS CASE 1: an empty canonical bundle fails the render, naming ${trace_id} and the collection"
fi

# ---------------------------------------------------------------------------
# CASE 2 -- each mapped collection, dropped alone, fails and names itself.
# ---------------------------------------------------------------------------
for name in canonicalRoutes canonicalSites canonicalForwarding canonicalRuntimeTargets; do
  partial="$(python3 - "${all_present}" "${name}" <<'PY'
import json, sys
d = json.loads(sys.argv[1])
d.pop(sys.argv[2], None)
print(json.dumps(d))
PY
)"
  out="$(render "${partial}")"
  if ! grep -qF "${name}" <<<"${out}"; then
    issues=$((issues + 1))
    {
      echo "FAIL CASE 2: dropping '${name}' did not fail the render naming it"
      echo "  got: ${out}"
    } >&2
  elif ! grep -qF "${trace_id}" <<<"${out}"; then
    issues=$((issues + 1))
    {
      echo "FAIL CASE 2: dropping '${name}' did not fail naming ${trace_id}"
      echo "  got: ${out}"
    } >&2
  else
    echo "PASS CASE 2: dropping '${name}' fails the render and names it"
  fi
done

# ---------------------------------------------------------------------------
# CASE 3 -- the seeded negative: with every collection present, the same render
# succeeds. This is what makes CASE 1 and CASE 2 evidence of a check rather than
# of a module that never evaluates.
# ---------------------------------------------------------------------------
present_out="$(render "${all_present}")"
if [[ "${present_out}" != "["* ]]; then
  issues=$((issues + 1))
  {
    echo "FAIL CASE 3: with all four canonical collections present the render still failed"
    echo "  got: ${present_out}"
  } >&2
else
  echo "PASS CASE 3: with all four canonical collections present the same render succeeds (the check can pass)"
fi

echo ""
if ((issues > 0)); then
  echo "FAIL NO-CANONICAL-REPAIR: ${issues} issue(s)." >&2
  echo "  The boundary is ${entry}; it must throw, not fall back to the plain CPM." >&2
  echo "  Do not repair it here: the collection belongs in the schema's list, then in" >&2
  echo "  the producer's bundle, then in this renderer's mapping." >&2
  exit 1
fi

echo "PASS NO-CANONICAL-REPAIR: a canonical collection the bundle does not carry crashes the render"
exit 0
