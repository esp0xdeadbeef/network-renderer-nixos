#!/usr/bin/env bash
# GAMP-ID: FS-310-HDS-010-SDS-010
# GAMP-SCOPE: software-module-test
#
# S88 LAYER CONFORMANCE — is the ISA-88 hierarchy this repository claims to
# implement actually implemented?
#
# FS-310-HDS-010-SDS-010 is the software design that owns the **S88 layout**
# (see README.md -> "Primary Chain: Renderer Policy Boundary"). This test is the
# executable form of that layout, so that the hierarchy cannot drift away from
# the design while every behavioural test stays green.
#
# WHAT NORM IS BEING ENFORCED
# ---------------------------
# The norm is the ISA-88 interpretation table published by the upstream stages
# of this pipeline (the compiler stage and the forwarding-model stage both carry
# the same table in their README). It is a *responsibility* table, not a
# directory listing:
#
#   Enterprise       administrative grouping
#   Site             authority boundary
#   Process Cell     allowed communication behavior
#   Unit             forwarding execution context
#   Equipment Module  responsibility of a forwarding unit
#   Control Module   implementation mechanism
#
# Read it before changing anything here. Two consequences are machine-checkable
# and are what this file checks:
#
#   (a) every level has ONE public surface (`api/`), so a consumer never has to
#       know a level's internal file layout;
#   (b) authority flows DOWNWARD. A level that *decides* (Site, Unit) is above a
#       level that *implements* (EquipmentModule, ControlModule). A lower level
#       importing a higher level's internals inverts the standard: the
#       implementation is then choosing the decision it is supposed to execute.
#
# THIS TEST FAILS TODAY. THAT IS THE POINT.
# ------------------------------------------
# It fails on the current tree. Do NOT make it pass by editing the checker,
# deleting a level from `levels`, or adding the level to `EXEMPT`. AGENTS.md
# "Fixing rules" rule 2 forbids a test that stops asserting; rule 1 says fix the
# root cause in the layer that owns the behaviour. If a finding below looks
# wrong, the document to argue with is the norm table, not this script.
set -euo pipefail

repo_root="${SMS_TEST_REPO_ROOT:-$(git -C "$(dirname "${BASH_SOURCE[0]}")" rev-parse --show-toplevel)}"
source "${repo_root}/tests/lib/direct-test-guard.sh" 2>/dev/null || true

# Hierarchy, highest authority first. The order IS the standard: index 1 is the
# widest scope, index 7 the narrowest implementation. `level_rank` returns the
# position; a numerically smaller rank is HIGHER (broader) authority.
levels=(Enterprise Site Area ProcessCell Unit EquipmentModule ControlModule)

level_rank() {
  case "$1" in
    Enterprise) echo 1 ;;
    Site) echo 2 ;;
    Area) echo 3 ;;
    ProcessCell) echo 4 ;;
    Unit) echo 5 ;;
    EquipmentModule) echo 6 ;;
    ControlModule) echo 7 ;;
    *) echo 99 ;;
  esac
}

# The only level directories exempt from the `api/default.nix` façade rule.
# Empty on purpose. An entry here is a claim that the level has no consumers,
# which for ControlModule is false by construction (it is imported from Unit,
# the flake, and the NixOS module entry points).
EXEMPT=()

issues=0

# report_issue <id> <one-line finding> <why it is a defect> <what to read>
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

norm_pointer="the ISA-88 interpretation table carried by the upstream compiler and
         forwarding-model stages (Enterprise=administrative grouping, Site=authority
         boundary, Process Cell=allowed communication behavior, Unit=forwarding
         execution context, Equipment Module=responsibility of a forwarding unit,
         Control Module=implementation mechanism). This repository's own claim is
         README.md -> FS-310-HDS-010-SDS-010 ('interface architecture, S88 layout')."

# ---------------------------------------------------------------------------
# L1 — the seven levels exist.
#
# The hierarchy is the standard. A missing level is not a tidy-up: it means the
# design document and the tree disagree, and every trace row that names that
# level is pointing at nothing.
# ---------------------------------------------------------------------------
for level in "${levels[@]}"; do
  if [[ ! -d "${repo_root}/s88/${level}" ]]; then
    report_issue "S88-L1" "level directory s88/${level} is missing" \
      "the S88 layout owned by FS-310-HDS-010-SDS-010 names seven levels; a test that
         cannot find one is asserting against a tree the design does not describe" \
      "${norm_pointer}"
  fi
done

# ---------------------------------------------------------------------------
# L2 — every level exposes exactly one public surface: api/default.nix.
#
# This is what makes the standard usable rather than aspirational. With a façade,
# a consumer says "give me the Unit surface". Without one, every consumer has to
# hardcode a path into another level's private directory, and the level can no
# longer be reorganised without touching its consumers.
# ---------------------------------------------------------------------------
for level in "${levels[@]}"; do
  [[ -d "${repo_root}/s88/${level}" ]] || continue

  exempt=0
  for entry in ${EXEMPT[@]+"${EXEMPT[@]}"}; do
    [[ "${entry}" == "${level}" ]] && exempt=1
  done
  ((exempt == 0)) || continue

  if [[ ! -f "${repo_root}/s88/${level}/api/default.nix" ]]; then
    report_issue "S88-L2" "s88/${level} has no api/default.nix façade" \
      "the level is consumable only by knowing its internal file layout. Every other
         level in this tree has a façade, so this one is the exception the design does
         not describe -- and it is the level with by far the most consumers" \
      "${norm_pointer}
         Also read s88/ControlModule/render/container-networks/policy-routing/TRACE.md,
         which assigns every ControlModule source file an S88 LAYER; a level that
         publishes a layer per file but no façade is the inversion this check names."
  fi
done

# ---------------------------------------------------------------------------
# L3 — the façades compose downward.
#
# Enterprise/api -> Site/api -> Area/api -> ProcessCell/api -> Unit/api ->
# ControlModule/api. Each level's façade must reach the next level through its
# façade, never through its internals. That chain is the whole reason the
# hierarchy can be consumed by a renderer without the renderer knowing the site
# model's file layout.
# ---------------------------------------------------------------------------
for ((i = 0; i < ${#levels[@]} - 1; i++)); do
  upper="${levels[i]}"
  lower="${levels[i + 1]}"
  façade="${repo_root}/s88/${upper}/api/default.nix"
  [[ -f "${façade}" ]] || continue

  if ! grep -qE "${lower}/api" "${façade}"; then
    report_issue "S88-L3" "s88/${upper}/api/default.nix does not reach the ${lower} façade" \
      "the public surface of ${upper} is supposed to compose the public surface of
         ${lower}. If it reaches into ${lower}'s internals instead (or not at all),
         the composition chain is broken at that level and no consumer above it can
         be layer-agnostic" \
      "${norm_pointer}"
  fi
done

# ---------------------------------------------------------------------------
# The scanner used by L4/L5. Kept as a function so the seeded negative below can
# run the *same* code against a fixture that is known to be non-conformant. A
# checker that cannot fail is not a checker.
#
# Emits TAB-separated lines:
#   UPWARD  <from-level> <to-level> <file>   lower level imports higher level
#   BYPASS  <from-level> <to-level> <file>   cross-level import skips <to>/api/
# ---------------------------------------------------------------------------
run_layer_scan() {
  local root="$1"
  local level to hit file content from_rank to_rank

  for level in "${levels[@]}"; do
    [[ -d "${root}/s88/${level}" ]] || continue
    while IFS= read -r hit; do
      [[ -n "${hit}" ]] || continue
      file="${hit%%:*}"
      content="${hit#*:}"
      content="${content#*:}"

      for to in "${levels[@]}"; do
        [[ "${to}" == "${level}" ]] && continue
        [[ "${content}" =~ (\.\./)+(s88/)?${to}/ ]] || continue

        from_rank="$(level_rank "${level}")"
        to_rank="$(level_rank "${to}")"

        if ((to_rank < from_rank)); then
          printf 'UPWARD\t%s\t%s\t%s\n' "${level}" "${to}" "${file#"${root}/"}"
        fi
        if [[ ! "${content}" =~ (\.\./)+(s88/)?${to}/api/ ]]; then
          printf 'BYPASS\t%s\t%s\t%s\n' "${level}" "${to}" "${file#"${root}/"}"
        fi
      done
    done < <(
      grep -rnE "(\.\./)+(s88/)?(Enterprise|Site|Area|ProcessCell|Unit|EquipmentModule|ControlModule)/" \
        "${root}/s88/${level}" --include='*.nix' 2>/dev/null || true
    )
  done
}

echo "--- FS-310-HDS-010-SDS-010: S88 layer conformance ---"
echo ""

mapfile -t scan_lines < <(run_layer_scan "${repo_root}")

# ---------------------------------------------------------------------------
# L4 — no upward dependency.
#
# This is the hard error. "Equipment Module = responsibility of a forwarding
# unit" and "Unit = forwarding execution context" are adjacent levels with a
# strict order of authority: the Unit decides the context, the Equipment Module
# performs the responsibility. An EquipmentModule file that imports Unit
# internals lets the responsibility re-derive its own context -- which is exactly
# how a renderer starts inventing the architecture it is only allowed to
# realise.
# ---------------------------------------------------------------------------
upward_count=0
for line in ${scan_lines[@]+"${scan_lines[@]}"}; do
  [[ "${line}" == UPWARD* ]] || continue
  IFS=$'\t' read -r _ from to file <<<"${line}"
  upward_count=$((upward_count + 1))
  report_issue "S88-L4" "${file}: ${from} imports ${to}, which is HIGHER in the hierarchy" \
    "authority flows downward only. ${from} is a responsibility/implementation level and
       ${to} is a decision level; this import makes the implementation depend on the
       decision it is meant to execute, so the decision can no longer change without
       changing the implementation" \
    "${norm_pointer}"
done

# ---------------------------------------------------------------------------
# L5 — cross-level imports go through the target level's façade.
#
# Downward imports are legitimate; bypassing the façade is not, because it makes
# the lower level's private layout part of the higher level's contract. When this
# fires in bulk for one target level, the diagnosis is not "add api/ to each
# import" -- it is that the target level has no façade to import (see L2).
# ---------------------------------------------------------------------------
bypass_count=0
declare -A bypass_by_level=()
for line in ${scan_lines[@]+"${scan_lines[@]}"}; do
  [[ "${line}" == BYPASS* ]] || continue
  IFS=$'\t' read -r _ from to file <<<"${line}"
  bypass_count=$((bypass_count + 1))
  bypass_by_level["${from}->${to}"]=$(( ${bypass_by_level["${from}->${to}"]:-0} + 1 ))
  echo "  BYPASS ${from} -> ${to}: ${file}" >&2
done

if ((bypass_count > 0)); then
  issues=$((issues + 1))
  {
    echo "ISSUE S88-L5: ${bypass_count} cross-level import(s) bypass the target level's api/ façade"
    echo "  distribution:"
    for key in "${!bypass_by_level[@]}"; do
      echo "    ${key}: ${bypass_by_level["${key}"]}"
    done | sort
    echo "  why:  a level's api/ is its contract. Importing a private file makes the"
    echo "        private layout part of the caller's contract, so the level can never"
    echo "        be reorganised and the trace row that names it stops being true."
    echo "  read: ${norm_pointer}"
    echo "        The ControlModule bulk entry is not 40 independent mistakes: it is the"
    echo "        L2 finding (no ControlModule façade) showing up once per consumer."
    echo
  } >&2
else
  echo "PASS S88-L5: every cross-level import targets an api/ façade"
fi

# ---------------------------------------------------------------------------
# Seeded negative — prove the scanner above discriminates.
#
# The fixture is a miniature hierarchy containing exactly the two defects L4 and
# L5 exist to catch. If the scanner reports zero here, the scanner is broken and
# every PASS it printed above is meaningless.
# ---------------------------------------------------------------------------
seeded_root="$(mktemp -d)"
trap 'rm -rf "${seeded_root}"' EXIT

mkdir -p \
  "${seeded_root}/s88/Unit/lookup" \
  "${seeded_root}/s88/EquipmentModule/mapping" \
  "${seeded_root}/s88/ControlModule/render"

cat >"${seeded_root}/s88/ControlModule/render/hidden.nix" <<'NIX'
{ }: { private = true; }
NIX
cat >"${seeded_root}/s88/Unit/lookup/upward.nix" <<'NIX'
# seeded negative: a cross-level import that skips the ControlModule façade
{ lib }: import ../../ControlModule/render/hidden.nix { }
NIX
cat >"${seeded_root}/s88/EquipmentModule/mapping/inverted.nix" <<'NIX'
# seeded negative: UPWARD dependency (EquipmentModule importing Unit internals)
{ lib }: import ../../Unit/lookup/upward.nix { }
NIX

mapfile -t seeded_lines < <(run_layer_scan "${seeded_root}")
seeded_upward=0
seeded_bypass=0
for line in ${seeded_lines[@]+"${seeded_lines[@]}"}; do
  [[ "${line}" == UPWARD* ]] && seeded_upward=$((seeded_upward + 1))
  [[ "${line}" == BYPASS* ]] && seeded_bypass=$((seeded_bypass + 1))
done

if ((seeded_upward < 1 || seeded_bypass < 1)); then
  report_issue "S88-SEED" "the layer scanner did not detect the seeded non-conformance" \
    "expected >=1 UPWARD and >=1 BYPASS in the fixture, got UPWARD=${seeded_upward}
       BYPASS=${seeded_bypass}. Every PASS this test printed is therefore not evidence" \
    "tests/test-s88-layer-conformance.sh -> run_layer_scan"
else
  echo "PASS S88-SEED: scanner detected the seeded upward and façade-bypass defects"
fi

# ---------------------------------------------------------------------------
# Verdict.
# ---------------------------------------------------------------------------
echo ""
echo "summary: upward=${upward_count} façade-bypass=${bypass_count} issues=${issues}"

if ((issues > 0)); then
  echo ""
  echo "FAIL FS-310-HDS-010-SDS-010 (S88 layer conformance): ${issues} issue(s)." >&2
  echo "  This test is red on purpose; it is the S88 layout acting as an assertion." >&2
  echo "  Read the documents named in each ISSUE block before changing any source." >&2
  exit 1
fi

echo "PASS FS-310-HDS-010-SDS-010 (S88 layer conformance)"
exit 0
