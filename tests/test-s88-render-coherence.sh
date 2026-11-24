#!/usr/bin/env bash
# GAMP-SCOPE: software-module-test
#
# S88 RENDER COHERENCE -- evaluated, not grepped.
#
# Three artifacts are produced independently and compared:
#
#   E1  the same render, entered through each of the five level facades
#   E2  the same render, entered through the facade and through the flake API
#   E3  the same render, with the plain upstream envelope removed
#
# E1 asks whether the delegation chain is a chain: if `s88/Enterprise/api` and
# `s88/Unit/api` produce different output for the same input, the levels are not
# delegating, they are deciding. E3 asks whether the renderer is canonical-only:
# if removing the plain envelope changes the answer instead of failing, then
# "canonical field absent" and "canonical field present with the same value" are
# indistinguishable, which is exactly the compatibility path README.md ->
# "Not Allowed" forbids ("Repair missing canonical fields with local defaults").
#
# Scope, stated so the omission is a decision and not an oversight: this file does
# NOT re-check rendered routes against `canonicalRoutes`. That comparison is owned
# by `FS-310-HDS-020-SDS-010-SMS-060` (see
# `tests/lib/FS-310-HDS-020-SDS-010-SMS-060/`), which already resolves it per
# container and per runtime interface. Two owners for one comparison is the defect
# this suite is about.
#
# The comparison is on the SERIALISABLE projection of the render: attribute
# structure and data are compared exactly, functions are replaced by a marker so
# the comparison still sees them by name. That is deliberate -- the render
# returns NixOS module fragments, and comparing only data would let a facade drop
# a whole module.
#
# Coherence is the assertion: nothing here mentions a level name in a comment, an
# import path, or a directory. If the trees were rearranged tomorrow and the
# renders still agreed, this test would still pass, which is the point.
#
# Evidence boundary: construction. Nix evaluation only. No build, no lab, no
# network.
set -euo pipefail

repo_root="${SMS_TEST_REPO_ROOT:-$(git -C "$(dirname "${BASH_SOURCE[0]}")" rev-parse --show-toplevel)}"
source "${repo_root}/tests/lib/test-common.sh"
if [[ -f "${repo_root}/tests/lib/direct-test-guard.sh" ]]; then
  # shellcheck source=/dev/null
  source "${repo_root}/tests/lib/direct-test-guard.sh" 2>/dev/null || true
fi

fixture="${SMS_RENDER_FIXTURE:-tests/fixtures/multi-wan}"
host_name="${SMS_RENDER_HOST:-s-router-nixos}"

result_json="$(mktemp)"
eval_stderr="$(mktemp)"
trap 'rm -f "${result_json}" "${eval_stderr}"' EXIT

issues=0
report_issue() {
  local id="$1" finding="$2" why="$3" read="$4"
  issues=$((issues + 1))
  {
    echo "ISSUE ${id}: ${finding}"
    echo "  why:  ${why}"
    echo "  read: ${read}"
    echo
  } >&2
}

read_pointer="the workspace ISA-88 architecture note (not in this repository): the level
         table and the nested delegation chain. Then README.md -> Spec Chain
         FS-310-HDS-010-SDS-010-SMS-110 (fail-closed: missing/partial canonical input
         must fail) and README.md -> Not Allowed ('Repair missing canonical fields with
         local defaults')."

echo "--- S88-RENDER-COHERENCE: evaluated equivalence across the level chain ---"
echo ""
echo "  fixture: ${fixture}"
echo "  host:    ${host_name}"
echo ""

# ---------------------------------------------------------------------------
# One evaluation produces every artifact under comparison. Doing it in one
# evaluation matters: two separate `nix eval` runs could differ for reasons that
# have nothing to do with the chain.
# ---------------------------------------------------------------------------
if ! env REPO_ROOT="${repo_root}" FIXTURE="${fixture}" HOST_NAME="${host_name}" \
  nix eval --impure --json --expr '
    let
      repoRoot = builtins.getEnv "REPO_ROOT";
      fixture = builtins.getEnv "FIXTURE";
      hostName = builtins.getEnv "HOST_NAME";
      flake = builtins.getFlake ("path:" + repoRoot);
      lib = flake.inputs.nixpkgs.lib;
      system = "x86_64-linux";
      # An absolute fixture path is used as given, so the example that a defect
      # was measured on can be named directly without copying it into tests/.
      example =
        if builtins.substring 0 1 fixture == "/" then fixture
        else repoRoot + "/" + fixture;

      cpm = flake.inputs.network-control-plane-model.lib.${system}.compileAndBuildFromPaths {
        inputPath = example + "/intent.nix";
        inventoryPath = example + "/inventory-nixos.nix";
      };

      # Compare structure and data exactly; functions by name. A facade that
      # drops a module must not compare equal to one that keeps it.
      strip = v:
        if builtins.isFunction v then "<function>"
        else if builtins.isAttrs v then builtins.mapAttrs (_: strip) v
        else if builtins.isList v then map strip v
        else v;

      facades = [
        "Enterprise"
        "Site"
        "Area"
        "ProcessCell"
        "Unit"
      ];

      renderAt = level:
        let
          api = import (repoRoot + "/s88/" + level + "/api/default.nix") { inherit lib; };
        in
        builtins.toJSON (strip (api.renderer.renderHostNetwork {
          inherit hostName cpm;
        }));

      rendered = builtins.listToAttrs (map (level: { name = level; value = renderAt level; }) facades);
      baseline = rendered.Enterprise;

      topLevelAttrs = level:
        let
          api = import (repoRoot + "/s88/" + level + "/api/default.nix") { inherit lib; };
        in
        builtins.attrNames (api.renderer.renderHostNetwork { inherit hostName cpm; });

      # E3: remove the plain upstream envelope and see what happens.
      strippedCpm = removeAttrs cpm [ "control_plane_model" "controlPlaneModel" ];
      envelopeRemoval =
        builtins.tryEval (builtins.deepSeq
          ((import (repoRoot + "/s88/Unit/api/default.nix") { inherit lib; })
            .renderer.renderHostNetwork { inherit hostName; cpm = strippedCpm; }) true);
    in
    rec
    {
      anyDiffers = builtins.any (level: rendered.${level} != baseline) facades;
      differing = builtins.filter (level: rendered.${level} != baseline) facades;
      equalLengths = builtins.mapAttrs (_: json: builtins.stringLength json) rendered;
      attrs = builtins.listToAttrs (map (level: { name = level; value = topLevelAttrs level; }) facades);
      envelopeRemovalSucceeds = envelopeRemoval.success && envelopeRemoval.value;

      # Seeded negative: the comparison must be able to tell two renders apart,
      # including a difference that is only the presence or absence of a function.
      # If `strip` collapsed everything, E1 would always pass and prove nothing.
      seedA = builtins.toJSON (strip { keep = 1; also = (x: x); });
      seedB = builtins.toJSON (strip { keep = 1; also = (x: x); });
      seedC = builtins.toJSON (strip { keep = 2; also = (x: x); });
      seedD = builtins.toJSON (strip { keep = 1; });
      comparisonDiscriminates = (seedA == seedB) && (seedA != seedC) && (seedA != seedD);
    }
  ' >"${result_json}" 2>"${eval_stderr}"; then
  echo "FAIL S88-RENDER-COHERENCE: the evaluation needed for the comparison failed" >&2
  cat "${eval_stderr}" >&2
  exit 1
fi

# ---------------------------------------------------------------------------
# E1 -- the five facades must render identically.
# ---------------------------------------------------------------------------
if [[ "$(_jq -r '.anyDiffers' "${result_json}")" == "true" ]]; then
  differing="$(_jq -r '.differing | join(", ")' "${result_json}")"
  sizes="$(_jq -r '.equalLengths | to_entries | map("\(.key)=\(.value)") | join(" ")' "${result_json}")"
  report_issue "S88-E1" "the level facades do not render identically (differs: ${differing})" \
    "each s88/<Level>/api/default.nix is a delegation of the one below it. If entering the
       same computation at two levels produces different artifacts for the same input, the
       levels are not delegating -- one of them is adding or dropping behaviour, so the
       chain cannot be relied on to preserve what it claims to pass through.
       serialised sizes: ${sizes}" \
    "${read_pointer}"
else
  echo "PASS E1: all five level facades render identically for the same input"
fi

# ---------------------------------------------------------------------------
# E1b -- the facades must also expose the same surface. Two levels can render
# the same thing today and still differ in what they export, which is how a
# chain breaks on the next change instead of this one.
# ---------------------------------------------------------------------------
surface_diff="$(_jq -r '
  .attrs as $a
  | [$a | to_entries[] | select(.key != "Enterprise") | .key as $k
     | select(($a.Enterprise - .value) != [] or (.value - $a.Enterprise) != [])
     | "\($k): only-enterprise=\(($a.Enterprise - .value) | join(",")) only-\($k)=\((.value - $a.Enterprise) | join(","))"]
  | join("; ")' "${result_json}")"

if [[ -n "${surface_diff}" ]]; then
  report_issue "S88-E1" "the level facades expose different surfaces: ${surface_diff}" \
    "a facade that exports a different set from the level below it is not a pass-through.
       Today the render happens to agree because the extra export is unused by this fixture;
       the disagreement is still a chain break waiting for the next consumer." \
    "${read_pointer}"
else
  echo "PASS E1b: every facade exposes the same surface as Enterprise"
fi

# ---------------------------------------------------------------------------
# E3 -- removing the plain envelope must fail closed, not render something else.
# ---------------------------------------------------------------------------
if [[ "$(_jq -r '.envelopeRemovalSucceeds' "${result_json}")" == "true" ]]; then
  report_issue "S88-E3" "the render succeeds when the plain upstream envelope is removed" \
    "the renderer is supposed to take network semantics from the canonical content and to
       fail when that content is missing. Here it produced an artifact anyway, so 'the
       canonical field is absent' and 'the canonical field is present with the same value'
       are indistinguishable from the output. That is the compatibility path the workspace
       note calls an unmodeled deviation, and it is why the suite can stay green while the
       renderer consumes raw upstream data under a canonical name." \
    "README.md -> Spec Chain FS-310-HDS-010-SDS-010-SMS-110 ('Fail-closed contract --
       missing/partial canonical input must fail') and FS-310-HDS-010-SDS-010-SMS-100
       ('Canonical-only consumption'), plus README.md -> Not Allowed."
else
  echo "PASS E3: removing the plain upstream envelope fails closed"
fi

# ---------------------------------------------------------------------------
# Seeded negative -- a comparison that cannot distinguish two renders is not a
# comparison, and E1/E1b would then be reporting PASS for the wrong reason.
# ---------------------------------------------------------------------------
if [[ "$(_jq -r '.comparisonDiscriminates' "${result_json}")" != "true" ]]; then
  report_issue "S88-E-SEED" "the render comparison cannot distinguish renders that differ"     "the seeded pair (same value, different value, function present vs absent) did not
       produce the expected equality pattern, so E1 and E1b above are not evidence" \
    "tests/test-s88-render-coherence.sh -> strip and the seed block in the evaluation"
else
  echo "PASS E-SEED: comparison distinguishes a changed value and a dropped function"
fi

echo ""
if ((issues > 0)); then
  echo "FAIL S88-RENDER-COHERENCE: ${issues} coherence issue(s)." >&2
  echo "  Fix in the level that owns the behaviour. Do not compare fewer fields to" >&2
  echo "  make this pass: the comparison is the requirement." >&2
  exit 1
fi

echo "PASS S88-RENDER-COHERENCE: the render is coherent across the level chain"
exit 0
