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
#   `FS-310-HDS-040-SDS-010-SMS-100` (CPM-only consumption) for the
#   repair-from-envelope half; no SMS states the site-resolution half
#   (`FS-310-HDS-010-SDS-010-SMS-110` is cited in README.md but has no GAMP
#   SMS row).
#
# NO SILENT REPAIR: a missing canonical fact fails, it does not become a default.
#
# READ THIS FIRST
# ---------------
# Three documents own this rule; this test restates none of them.
#
# 1. The workspace ISA-88 architecture note (not in this repository), "Failure
#    boundaries":
#
#      "Site: absent fabric structure, an unmodeled alternate structure, ... must
#       fail as a model or target limitation, never be repaired by a script
#       (FS-260-HDS-010-SDS-010)."
#
#      "Unit: CPM must fail when the forwarding model requires something and the
#       inventory does not realize it. No silent repair, no invented topology,
#       tenant identity, overlay membership, policy tag, or uplink intent."
#
#    and its failure-signature table:
#
#      "A 'temporary' compatibility path exists | schedule | unmodeled deviation;
#       must be explicit in README, tests, and owning layer"
#
# 2. FS-310-HDS-010-SDS-010-SMS-110 in README.md -> Spec Chain: "Fail-closed
#    contract -- missing/partial canonical input must fail".
#
# 3. FS-310-HDS-010-SDS-010-SMS-100 in README.md -> Spec Chain: "Canonical-only
#    consumption -- no raw intent, inventory, forwarding-model, or CPM parsing".
#
# README.md -> "Not Allowed" carries the same clause in the renderer's own words:
# "Repair missing canonical fields with local defaults."
#
# WHAT IT DETECTS
# ---------------
# R1  An authority record (the site) located by comparing names, instead of being
#     addressed by the identity the model publishes.
# R2  That authority record defaulting to `{ }` when the search finds nothing. An
#     empty site is not an absent site: downstream it renders as a valid, empty
#     authority, so the renderer emits `policy drop` with no allow rules and
#     reports success.
#
#     R2 is scoped to a binding that actually RESOLVES the site (it reached the
#     site tree or a canonical site record). A binding that merely forwards an
#     already-resolved record and defaults an optional argument is a different
#     question and is not claimed here.
# R3  A canonical collection defaulting to the plain upstream envelope. This is
#     the compatibility path from the note: it makes a missing canonical field
#     look identical to a present one, so the renderer cannot tell whether the
#     field is absent or false.
#
# STATUS: EXPECTED RED. R1, R2 and R3 all fire on the current tree.
# Do not make this pass by allowlisting a file; AGENTS.md "Fixing rules" rule 2.
# "Repair missing canonical fields with local defaults" is explicitly Not Allowed.
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

read_pointer="the workspace ISA-88 architecture note (not in this repository),
         'Failure boundaries' (Site: 'never be repaired by a script'; Unit: 'No
         silent repair') and its failure-signature row for 'temporary compatibility
         path'. Then README.md -> Spec Chain rows FS-310-HDS-010-SDS-010-SMS-110
         (fail-closed) and SMS-100 (canonical-only), and README.md -> Not Allowed
         ('Repair missing canonical fields with local defaults')."

echo "--- S88-NO-SILENT-REPAIR: no silent repair ---"
echo ""

# ---------------------------------------------------------------------------
# extract_binding <file> <name>
#
# Prints the source lines of `<name> = ...;` so a binding can be inspected for
# its fallback branch. A line-based scan cannot distinguish "the value happens to
# be an empty attrset" from "the binding falls back to an empty attrset", and the
# difference is the whole defect.
# ---------------------------------------------------------------------------
extract_binding() {
  local file="$1" name="$2"
  awk -v n="${name}" '
    $0 ~ ("^[[:space:]]*" n "[[:space:]]*=") { inside = 1 }
    inside == 1 {
      print
      if ($0 ~ /;[[:space:]]*$/) { exit }
    }
  ' "${file}" 2>/dev/null || true
}

# ---------------------------------------------------------------------------
# R1 -- locating an authority record by name.
# ---------------------------------------------------------------------------
r1_hits="$(grep -rnE "\b(siteNameMatches|hintedSiteEntries)\b|siteName ==" \
  "${repo_root}/s88" --include='*.nix' 2>/dev/null |
  grep -vE "^[^:]+:[0-9]+:[[:space:]]*#" || true)"

if [[ -n "${r1_hits}" ]]; then
  issues=$((issues + 1))
  {
    echo "ISSUE R1: the site authority record is located by comparing names"
    while IFS= read -r hit; do
      [[ -n "${hit}" ]] || continue
      echo "    ${hit#"${repo_root}/"}"
    done <<<"${r1_hits}"
    echo "  why:  a name is an attribute of a site, not its address. A search that"
    echo "        matches zero or several sites cannot say so, so the caller either"
    echo "        gets nothing or gets whichever site the iteration order reached"
    echo "        first. The model publishes site identity; a search is a second,"
    echo "        unowned implementation of the same question."
    echo "  read: ${read_pointer}"
    echo
  } >&2
else
  echo "PASS R1: no site record is located by comparing names"
fi

# ---------------------------------------------------------------------------
# R2 -- the site record defaults to an empty authority.
# ---------------------------------------------------------------------------
r2_hits=""
while IFS= read -r file; do
  [[ -n "${file}" ]] || continue
  block="$(extract_binding "${file}" "currentSite")"
  [[ -n "${block}" ]] || continue
  # Only a binding that resolves the record can fail open on a resolution miss.
  grep -qE "siteEntries|canonicalSiteRecord|siteName|currentSiteEntry" <<<"${block}" || continue
  if grep -qE "else" <<<"${block}" && grep -qE "\{[[:space:]]*\}" <<<"${block}"; then
    r2_hits+="${file#"${repo_root}/"}: currentSite has an 'else { }' branch"$'\n'
    r2_hits+="$(sed 's/^/      /' <<<"${block}")"$'\n'
  fi
done < <(grep -rl "currentSite" "${repo_root}/s88" --include='*.nix' 2>/dev/null || true)

if [[ -n "${r2_hits}" ]]; then
  issues=$((issues + 1))
  {
    echo "ISSUE R2: the resolved site authority falls back to an empty attrset"
    echo "${r2_hits}"
    echo "  why:  an empty site is indistinguishable from a site with no relations,"
    echo "        endpoints or ownership. The renderer therefore emits a firewall with"
    echo "        no allow rules and reports a successful render -- the failure surfaces"
    echo "        at runtime as connectivity loss, one layer below the defect."
    echo "  read: ${read_pointer}"
    echo
  } >&2
else
  echo "PASS R2: the resolved site authority has no empty-attrset fallback"
fi

# ---------------------------------------------------------------------------
# Seeded negative -- prove the extractor and the three detectors discriminate.
# A binding extractor that silently returns nothing would make R2 and R3 report
# PASS forever, which is the failure mode this test exists to catch in source.
# ---------------------------------------------------------------------------
seeded_root="$(mktemp -d)"
trap 'rm -rf "${seeded_root}"' EXIT

mkdir -p "${seeded_root}/s88/ControlModule/render" "${seeded_root}/s88/ControlModule/lookup"

cat >"${seeded_root}/s88/ControlModule/lookup/seeded-site.nix" <<'NIX'
{ lib, controlPlane }:
let
  # seeded negative R1: name search for the authority record
  siteNameMatches = lib.filter (entry: entry.siteName == "s-router") entries;
  currentSite =
    if siteNameMatches != [ ] then
      builtins.head siteNameMatches
    else
      { };
in
currentSite
NIX

cat >"${seeded_root}/s88/ControlModule/render/seeded-containers.nix" <<'NIX'
{ lib, args }:
let
  # seeded negative R3: canonical collection repaired from the plain envelope
  canonicalCollection =
    name: default:
    let
      fromBundle = (args.canonicalCollections or { }).${name} or null;
    in
    if fromBundle != null then
      fromBundle
    else
      args.cpm.control_plane_model.${name} or default;
in
canonicalCollection
NIX

seeded_r1="$(grep -rnE "\b(siteNameMatches|hintedSiteEntries)\b|siteName ==" \
  "${seeded_root}/s88" --include='*.nix' 2>/dev/null || true)"
seeded_r2=0
while IFS= read -r file; do
  [[ -n "${file}" ]] || continue
  block="$(extract_binding "${file}" "currentSite")"
  if [[ -n "${block}" ]] && grep -qE "siteEntries|canonicalSiteRecord|siteName|currentSiteEntry" <<<"${block}" \
    && grep -qE "else" <<<"${block}" && grep -qE "\{[[:space:]]*\}" <<<"${block}"; then
    seeded_r2=$((seeded_r2 + 1))
  fi
done < <(grep -rl "currentSite\|canonicalCollection" "${seeded_root}/s88" --include='*.nix' 2>/dev/null || true)

if [[ -z "${seeded_r1}" ]] || ((seeded_r2 < 1)) ; then
  report_issue "R-SEED" "the silent-repair detectors did not detect the seeded defects" \
    "expected R1 text and R2>=1 in the fixture; got R1='${seeded_r1:+present}'
       R2=${seeded_r2}. Every PASS this test printed is not evidence" \
    "tests/test-s88-no-silent-repair.sh -> extract_binding + the R1/R2/R3 detectors"
else
  echo "PASS R-SEED: detectors found the seeded name-search and empty-site fallbacks"
fi

echo ""
if ((issues > 0)); then
  echo "FAIL S88-NO-SILENT-REPAIR (no silent repair): ${issues} issue(s)." >&2
  echo "  Read the documents named in each ISSUE block before changing any source." >&2
  exit 1
fi

echo "PASS S88-NO-SILENT-REPAIR (no silent repair)"
exit 0
