#!/usr/bin/env bash
# GAMP-SCOPE: repository architecture conformance guard; not SMT acceptance
# evidence -- no SMS row exists yet (see TRACE NOTE).
#
# TRACE NOTE
# ----------
# This file carries no `# GAMP-ID:` header on purpose. `GAMP/methodology/
# trace-chain-ids.md` requires a test's header to be a FULL trace chain ending
# in `SMS-NNN`, and the layer rule is "no CMC/test without SMS". No SMS row owns
# this predicate yet, so citing the SDS (`FS-310-HDS-010-SDS-010`) or inventing
# an SMS number would be false traceability. The precedent in this repository is
# `tests/test-no-private-mirror-reference.sh`, which is a repository guard with a
# `GAMP-SCOPE` and no ID.
#
# Recorded gap, to be closed in the owning GAMP layer:
#   `FS-310-HDS-020-SDS-010-SMS-060` (route command source binding) for the
#   route/lane half; no SMS states the behaviour-class half.
#
# AUTHORITY MUST NOT BE RECOVERED FROM DERIVATION.
#
# READ THIS FIRST
# ---------------
# The workspace ISA-88 architecture note (not in this repository) states the rule
# this test enforces, in its Control Module section:
#
#   "A control module must never become the only place a decision is recorded. If
#    a renderer needs lane selection, route ownership, overlay semantics, or
#    forwarding authority, that must appear as explicit model data on the way
#    down -- never recovered by parsing link names, provider names, role names, or
#    example files."
#
# and it lists the symptom under "Failure signatures worth recognizing":
#
#   "Reasoning requires reading link names or file names -> authority is being
#    recovered from derivation."
#
# The functional statement is FS-310-HDS-020-SDS-010-SMS-060:
#
#   "The renderer shall not choose, infer, or withhold a route's table or lane
#    occurrence: it shall not gate a route's materialization on the presence of a
#    forwarding rule, derive occurrence from interface topology, or rely on an
#    environment-supplied fallback table."
#
# This test does not restate those rules. It detects their violation.
#
# WHAT IT DETECTS
# ---------------
# A1  Route/lane/role authority authored by the renderer from the interface-class
#     taxonomy (`hasClass`, `sameAccess`, `sameUplink`).
#
#     The class flags themselves (edgeFacing, fabricFacing, coreFacing,
#     exitFacing) are legitimate canonical data -- they are published by the
#     upstream model stages. What is not legitimate is using them to *create* an
#     authorization: which interfaces feed which policy table, and which behavior
#     class a node belongs to, must arrive as data, not be recomputed here.
#
# A2  Canonical record ownership selected by string arithmetic on target names
#     rather than by the canonical target identity the model publishes.
#
# STATUS: EXPECTED RED. Both A1 and A2 fire on the current tree.
# Do not make this pass by widening the detector or by deleting a finding from
# `derivation_files`; AGENTS.md "Fixing rules" rules 1 and 2. If a finding is
# genuinely misclassified, the argument is with the two quoted paragraphs, not
# with this script.
#
# Evidence boundary: construction. Static file reads only. No evaluation, no
# build, no lab, no network.
set -euo pipefail

repo_root="${SMS_TEST_REPO_ROOT:-$(git -C "$(dirname "${BASH_SOURCE[0]}")" rev-parse --show-toplevel)}"
source "${repo_root}/tests/lib/direct-test-guard.sh" 2>/dev/null || true

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

read_pointer="the workspace ISA-88 architecture note (not in this repository), Control
         Module section ('A control module must never become the only place a decision
         is recorded... never recovered by parsing link names, provider names, role
         names, or example files') and its failure-signature table ('Reasoning
         requires reading link names or file names -> authority is being recovered
         from derivation'). The functional clause is FS-310-HDS-020-SDS-010-SMS-060:
         a renderer shall not 'derive occurrence from interface topology'."

echo "--- S88-AUTHORITY: authority not recovered from derivation ---"
echo ""

# ---------------------------------------------------------------------------
# The detector. Kept as a function so the seeded negative below runs the same
# code against a fixture that is known to be non-conformant.
#
# Emits TAB-separated:  <KIND>  <file:line>  <detail>
# ---------------------------------------------------------------------------
run_derivation_scan() {
  local root="$1"

  # A1 -- the three primitives that let a file mint an authorization out of the
  # interface-class taxonomy. Any one of them in a renderer source file means the
  # file is answering "which interfaces are authorized" on its own.
  grep -rnE "\b(hasClass|sameAccess|sameUplink)\b" "${root}/s88" --include='*.nix' 2>/dev/null |
    grep -vE "^[^:]+:[0-9]+:[[:space:]]*#" |
    while IFS= read -r hit; do
      [[ -n "${hit}" ]] || continue
      file="${hit%%:*}"
      rest="${hit#*:}"
      lineno="${rest%%:*}"
      detail="${rest#*:}"
      printf 'A1\t%s:%s\t%s\n' "${file#"${root}/"}" "${lineno}" "$(echo "${detail}" | sed 's/^[[:space:]]*//' | cut -c1-100)"
    done

  # A2 -- string arithmetic against a target name. Selecting a container's
  # canonical records this way re-derives ownership from a naming convention.
  local cn="${root}/s88/ControlModule/render/container-networks.nix"
  if [[ -f "${cn}" ]]; then
    grep -nE "builtins\.(substring|stringLength)" "${cn}" 2>/dev/null |
      while IFS= read -r hit; do
        [[ -n "${hit}" ]] || continue
        lineno="${hit%%:*}"
        detail="${hit#*:}"
        printf 'A2\t%s:%s\t%s\n' "${cn#"${root}/"}" "${lineno}" "$(echo "${detail}" | sed 's/^[[:space:]]*//' | cut -c1-100)"
      done
  fi
}

mapfile -t scan_lines < <(run_derivation_scan "${repo_root}")

a1_count=0
a2_count=0
declare -A a1_by_file=()
declare -A a2_by_file=()

for line in ${scan_lines[@]+"${scan_lines[@]}"}; do
  [[ -n "${line}" ]] || continue
  IFS=$'\t' read -r kind where detail <<<"${line}"
  case "${kind}" in
    A1)
      a1_count=$((a1_count + 1))
      file="${where%:*}"
      a1_by_file["${file}"]=$(( ${a1_by_file["${file}"]:-0} + 1 ))
      echo "  A1 ${where}: ${detail}" >&2
      ;;
    A2)
      a2_count=$((a2_count + 1))
      file="${where%:*}"
      a2_by_file["${file}"]=$(( ${a2_by_file["${file}"]:-0} + 1 ))
      echo "  A2 ${where}: ${detail}" >&2
      ;;
  esac
done

# ---------------------------------------------------------------------------
# A1 findings, grouped by file: the file is the unit of responsibility, and the
# grouping is what tells a reader whether this is one decision or forty.
# ---------------------------------------------------------------------------
if ((a1_count > 0)); then
  issues=$((issues + 1))
  {
    echo "ISSUE A1: ${a1_count} line(s) in ${#a1_by_file[@]} file(s) mint route/lane/role authority from the interface-class taxonomy"
    echo "  files:"
    for file in "${!a1_by_file[@]}"; do
      echo "    ${file} (${a1_by_file["${file}"]} line(s))"
    done | sort
    echo "  why:  the class flags are canonical data; the authorization computed from"
    echo "        them is not. Because the upstream stages publish no such authorization,"
    echo "        these files are the sole author of every source set and every behaviour"
    echo "        class, so the rendered route placement has no model item behind it and"
    echo "        cannot be checked against one."
    echo "  read: ${read_pointer}"
    echo
  } >&2
else
  echo "PASS A1: no renderer source authors route/lane/role authority from interface class"
fi

# ---------------------------------------------------------------------------
# A2 findings.
# ---------------------------------------------------------------------------
if ((a2_count > 0)); then
  issues=$((issues + 1))
  {
    echo "ISSUE A2: ${a2_count} line(s) select canonical records by string arithmetic on target names"
    echo "  files:"
    for file in "${!a2_by_file[@]}"; do
      echo "    ${file} (${a2_by_file["${file}"]} line(s))"
    done | sort
    echo "  why:  a name suffix is a naming convention, not an identity. Two targets can"
    echo "        share a suffix, a target can be renamed, and the match silently falls"
    echo "        back to the empty set -- which reads as 'this node declares no routes'"
    echo "        rather than as a failure. The model publishes the target identity; use it."
    echo "  read: ${read_pointer}"
    echo "        Also FS-310-HDS-010-SDS-010-SMS-120 (no naming inference) in README.md."
    echo
  } >&2
else
  echo "PASS A2: canonical records are not selected by string arithmetic on names"
fi

# ---------------------------------------------------------------------------
# Seeded negative -- prove both detectors discriminate.
#
# The fixture contains one instance of each defect class. If the scanner reports
# zero here, every PASS above is not evidence.
# ---------------------------------------------------------------------------
seeded_root="$(mktemp -d)"
trap 'rm -rf "${seeded_root}"' EXIT

mkdir -p "${seeded_root}/s88/ControlModule/render"

cat >"${seeded_root}/s88/Unit-derived.nix" <<'NIX'
{ lib }:
interfaces:
let
  # seeded negative: mints lane authority from the interface-class taxonomy
  hasClass = flag: name: (interfaces.${name}.interfaceClass.${flag} or false);
  sameAccess = left: right: interfaces.${left}.lane == interfaces.${right}.lane;
in
lib.filter (name: hasClass "fabricFacing" name && sameAccess "eth0" name) (builtins.attrNames interfaces)
NIX

cat >"${seeded_root}/s88/ControlModule/render/container-networks.nix" <<'NIX'
# seeded negative: selects canonical records by target-name suffix arithmetic
{ canonicalRoutes }:
let
  logicalName = "s-router-policy";
  suffix = "-" + logicalName;
  n = builtins.stringLength target;
in
builtins.filter (r: builtins.substring (n - 5) 5 r.target == suffix) canonicalRoutes
NIX

mapfile -t seeded_lines < <(run_derivation_scan "${seeded_root}")
seeded_a1=0
seeded_a2=0
for line in ${seeded_lines[@]+"${seeded_lines[@]}"}; do
  [[ "${line}" == A1* ]] && seeded_a1=$((seeded_a1 + 1))
  [[ "${line}" == A2* ]] && seeded_a2=$((seeded_a2 + 1))
done

if ((seeded_a1 < 1 || seeded_a2 < 1)); then
  report_issue "A-SEED" "the derivation scanner did not detect the seeded defects" \
    "expected >=1 A1 and >=1 A2 in the fixture, got A1=${seeded_a1} A2=${seeded_a2}.
       Every PASS this test printed is therefore not evidence" \
    "tests/test-s88-authority-not-derived.sh -> run_derivation_scan"
else
  echo "PASS A-SEED: scanner detected the seeded A1 and A2 defects"
fi

echo ""
if ((issues > 0)); then
  echo "FAIL S88-AUTHORITY (authority not derived): ${issues} issue(s)." >&2
  echo "  Read the workspace ISA-88 architecture note before changing the detector." >&2
  exit 1
fi

echo "PASS S88-AUTHORITY (authority not recovered from derivation)"
exit 0
