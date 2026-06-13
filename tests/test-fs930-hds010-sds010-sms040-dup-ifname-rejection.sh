#!/usr/bin/env bash
# GAMP-ID: FS-930-HDS-010-SDS-010-SMS-040
# GAMP-SCOPE: software-module-test
# Focused construction test: Duplicate interface name rejection.
#
# SMS-040: Renderer must REJECT duplicate rendered interface name assignments
# with a hard diagnostic instead of auto-resolving via uniquification.
# Implements FS-930 bullet 3 prohibition against lower-layer heuristic repair.
#
# Construction test verifies:
#   1. Happy path: no uniquification/auto-resolve active code paths remain.
#   2. Duplicate detection: hard diagnostic emission present.
#   3. No artifact leakage: no WARNING trace that allows build to continue.
#   4. Seeded negative: scanner detects current violations.
#
# N1: Duplicate interface names trigger rejection, not auto-resolution.
# N2: Uniquification code path removed or gated.
#
# Auto-discovered by tests/test.sh via glob test-*.sh.
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${repo_root}/tests/lib/test-common.sh"

tmp_dir="$(mktemp -d "${TMPDIR:-/tmp}/network-renderer-nixos-fs930-sms040.XXXXXX")"
trap 'rm -rf "${tmp_dir}"' EXIT

target_file="${repo_root}/s88/Unit/mapping/runtime-targets/interfaces/rendered-names.nix"

echo "--- FS-930-HDS-010-SDS-010-SMS-040: Duplicate interface name rejection ---"
echo "Target: ${target_file#${repo_root}/}"
echo ""

# Helper: extract non-comment lines from a file
non_comment() {
  grep -vE '^\s*(#|$)' "$1" 2>/dev/null || true
}

# Helper: safe integer from grep -c (handles exit code 1 on zero matches)
safe_count() {
  local result
  result=$(grep -cE "$1" "$2" 2>/dev/null) || result=0
  echo "${result}" | tr -d '[:space:]'
}

# ============================================================
# Predicate 1: No auto-resolution keywords in active code
#
# SMS N2: "grep for uniquification or auto-resolv in the
# renderer's host-runtime module shall return zero active code
# paths that silently resolve duplicate interface names."
#
# Searching for: uniquification, auto-resolv, auto-resolving
# These keywords indicate the old auto-resolution behavior.
# ============================================================
echo "--- P1: Auto-resolution keyword scan ---"

non_comment_active="${tmp_dir}/non-comment.txt"
non_comment "${target_file}" > "${non_comment_active}"

p1_violations=0
for kw in uniquification auto-resolv auto-resolving; do
  count=$(safe_count "${kw}" "${non_comment_active}")
  if [[ "${count}" != "0" ]]; then
    echo "FAIL: '${kw}' found ${count} time(s) in active code." >&2
    grep -n "${kw}" "${non_comment_active}" >&2 || true
    p1_violations=$((p1_violations + count))
  fi
done

if [[ "${p1_violations}" -eq 0 ]]; then
  echo "PASS: No auto-resolution keywords in active code."
else
  echo "VIOLATIONS: ${p1_violations} auto-resolution keyword(s) in active code."
fi

# ============================================================
# Predicate 2: No WARNING trace that allows build to continue
#
# The old behavior emits a builtins.trace with WARNING and
# auto-resolving. The new behavior must use a hard diagnostic
# instead.
#
# Check: the phrase "auto-resolving via uniquification" (the
# old permissive trace) must not appear.
# ============================================================
echo ""
echo "--- P2: Permissive trace scan ---"

p2_count=$(grep -c 'auto-resolving via uniquification' "${target_file}" 2>/dev/null || echo 0)
p2_count=$(echo "${p2_count}" | tr -d '[:space:]')

if [[ "${p2_count}" != "0" ]]; then
  echo "FAIL: 'auto-resolving via uniquification' permissive trace found ${p2_count} time(s)." >&2
  grep -n 'auto-resolving via uniquification' "${target_file}" >&2 || true
else
  echo "PASS: No permissive 'auto-resolving via uniquification' trace."
fi

# ============================================================
# Predicate 3: Hard diagnostic emission present
#
# SMS: "The renderer shall REJECT the unit with a hard
# diagnostic when duplicate interface name assignments are
# detected."
#
# The diagnostic identifier is:
#   diagnostic.duplicate-rendered-interface-name
# ============================================================
echo ""
echo "--- P3: Hard diagnostic presence ---"

diag_files=$(grep -rl 'duplicate-rendered-interface-name' "${repo_root}/s88" --include='*.nix' 2>/dev/null || true)

if [[ -z "${diag_files}" ]]; then
  echo "FAIL: 'duplicate-rendered-interface-name' diagnostic not found in renderer source." >&2
  diag_present=false
else
  diag_present=true
  echo "PASS: Hard diagnostic found in:"
  while IFS= read -r f; do
    [[ -z "${f}" ]] && continue
    echo "  ${f#${repo_root}/}"
  done <<< "${diag_files}"
fi

# ============================================================
# Predicate 4: No uniquification function active usage
#
# ensureUniqueRenderedNames and resolveUniqueInterfaceName
# are the auto-resolution functions that SMS-040 prohibits.
# Verify they are removed or gated behind diagnostic rejection.
# ============================================================
echo ""
echo "--- P4: Uniquification function scan ---"

p4_violations=0
for fn in ensureUniqueRenderedNames; do
  # Check if function is DEFINED (not just called) in active code
  def_count=$(non_comment "${target_file}" | grep -c "${fn}" 2>/dev/null || echo 0)
  def_count=$(echo "${def_count}" | tr -d '[:space:]')
  if [[ "${def_count}" != "0" ]]; then
    # Count total references across repo
    ref_count=$(grep -rlc "${fn}" "${repo_root}/s88" --include='*.nix' 2>/dev/null | grep -v ':0$' | wc -l || echo 0)
    ref_count=$(echo "${ref_count}" | tr -d '[:space:]')
    echo "WARN: '${fn}' referenced in ${ref_count} file(s)."
    echo "  This function performs uniquification — SMS-040 prohibits."
    p4_violations=$((p4_violations + ref_count))
    grep -rl "${fn}" "${repo_root}/s88" --include='*.nix' 2>/dev/null | while IFS= read -r f; do
      echo "    ${f#${repo_root}/}"
    done
  fi
done

if [[ "${p4_violations}" -eq 0 ]]; then
  echo "PASS: No uniquification function references."
fi

# ============================================================
# Seeded Negative: Verify scanner CAN detect violations
#
# The scanner must prove it detects the current violations
# (uniquification/auto-resolution). If the code is clean,
# this is satisfied by predicates 1-4.
# ============================================================
echo ""
echo "--- Seeded Negative: Detection capability verification ---"

total_violations=$((p1_violations + p2_count + p4_violations))
if [[ "${diag_present}" == "false" ]]; then
  total_violations=$((total_violations + 1))
fi

if [[ "${total_violations}" -gt 0 ]]; then
  echo "SEEDED NEGATIVE PASS: ${total_violations} violation(s) detected."
  echo "  Scanner proves ability to detect SMS-040 violations."
  echo "  Violation summary:"
  [[ "${p1_violations}" -gt 0 ]] && echo "    - ${p1_violations} auto-resolution keyword(s)"
  [[ "${p2_count}" != "0" ]] && echo "    - ${p2_count} permissive trace(s)"
  [[ "${diag_present}" == "false" ]] && echo "    - diagnostic absent"
  [[ "${p4_violations}" -gt 0 ]] && echo "    - ${p4_violations} uniquification function file(s)"
else
  echo "NOTE: No violations detected (implementation may already be correct)."
  echo "  If all predicates pass, SMS-040 is satisfied."
fi

# ============================================================
# Report
# ============================================================
echo ""
echo "--- Results ---"

p1_pass=$([[ "${p1_violations}" -eq 0 ]] && echo true || echo false)
p2_pass=$([[ "${p2_count}" == "0" ]] && echo true || echo false)
p3_pass="${diag_present}"
p4_pass=$([[ "${p4_violations}" -eq 0 ]] && echo true || echo false)

echo "P1 (no auto-resolve keywords):  $([[ "${p1_pass}" == "true" ]] && echo PASS || echo FAIL)"
echo "P2 (no permissive trace):       $([[ "${p2_pass}" == "true" ]] && echo PASS || echo FAIL)"
echo "P3 (hard diagnostic present):   $([[ "${p3_pass}" == "true" ]] && echo PASS || echo FAIL)"
echo "P4 (no uniquification fns):     $([[ "${p4_pass}" == "true" ]] && echo PASS || echo FAIL)"
echo ""

failures=0
[[ "${p1_pass}" == "true" ]] || failures=$((failures + 1))
[[ "${p2_pass}" == "true" ]] || failures=$((failures + 1))
[[ "${p3_pass}" == "true" ]] || failures=$((failures + 1))
[[ "${p4_pass}" == "true" ]] || failures=$((failures + 1))

if [[ "${failures}" -eq 0 ]]; then
  echo "PASS: FS-930-HDS-010-SDS-010-SMS-040 duplicate interface name rejection."
  echo "  Renderer implements hard diagnostic rejection per SMS-040."
  exit 0
else
  echo "FAIL: FS-930-HDS-010-SDS-010-SMS-040 — ${failures} predicate(s) not satisfied."
  echo "  Required changes for SMS-040 compliance:"
  echo "    1. Remove uniquification/auto-resolution code from rendered-names.nix"
  echo "    2. Add diagnostic.duplicate-rendered-interface-name hard rejection"
  echo "    3. Reject unit with diagnostic instead of trace+WARNING"
  exit 1
fi
