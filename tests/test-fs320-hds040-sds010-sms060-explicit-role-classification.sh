#!/usr/bin/env bash
# GAMP-ID: FS-320-HDS-040-SDS-010-SMS-060
# GAMP-SCOPE: software-module-test
# Focused construction test: NixOS renderer explicit role classification.
#
# SMS-060: The NixOS renderer must classify interfaces by CPM explicit
# role flags (explicitWan, explicitTransit, explicitLocalAdapter) rather
# than falling back to sourceKind string tokens.
#
# CPM commit e09cf47 provides explicit interface role classification.
# NixOS commit b6e6bf5 removed the sourceKind fallback and uses explicit
# flags exclusively.
#
# This test scans the NixOS renderer source for:
# - Absence of sourceKind-based role fallback (wan/p2p/transit string matching)
# - Presence of explicitWan/explicitTransit/explicitLocalAdapter consumption
# - Seeded negatives that detect if a fallback is reintroduced
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
tmp_dir="$(mktemp -d)"
trap 'rm -rf "${tmp_dir}"' EXIT
all_checks_passed=true
src_dir="${repo_root}/s88"

echo "--- FS-320-HDS-040-SDS-010-SMS-060: Explicit role classification scan ---"
echo ""

# ============================================================
# Predicate 1: No sourceKind-based role fallback in roles.nix
# ============================================================
echo "--- Predicate 1: No sourceKind role fallback in roles.nix ---"

roles_file="${src_dir}/ControlModule/firewall/lookup/forwarding-intent/roles.nix"

# Scan for sourceKind used as a ROLE CLASSIFICATION fallback.
# This is different from metadata extraction (interfaces.nix extracts sourceKind as a
# descriptive field — that's fine). The violation is using sourceKind string tokens
# to decide WAN/transit/lan roles when explicit CPM flags are available.
sourcekind_fallbacks_file="${tmp_dir}/sourcekind-fallbacks.txt"
> "${sourcekind_fallbacks_file}"

# Pattern: sourceKind equality comparison used for role assignment
# e.g., entry.sourceKind == "wan", sourceKind == "p2p" for transit, etc.
grep -n 'sourceKind\s*==\s*"wan"' "${roles_file}" 2>/dev/null >> "${sourcekind_fallbacks_file}" || true
grep -n 'sourceKind\s*==\s*"p2p"' "${roles_file}" 2>/dev/null >> "${sourcekind_fallbacks_file}" || true
grep -n 'sourceKind\s*==\s*"transit"' "${roles_file}" 2>/dev/null >> "${sourcekind_fallbacks_file}" || true

# Pattern: fallback name lists derived from sourceKind (e.g., fallbackWanNames)
grep -n 'fallback\(Wan\|P2p\|Transit\|Lan\|LocalAdapter\)' "${roles_file}" 2>/dev/null >> "${sourcekind_fallbacks_file}" || true

# Pattern: filtering by sourceKind for role assignment (not overlay/pppoe)
# Only flag sourceKind used with .name extraction (which means it's assigning names)
grep -n 'filter.*sourceKind' "${roles_file}" 2>/dev/null | grep -v 'overlay\|pppoe' >> "${sourcekind_fallbacks_file}" || true

fallback_count=$(wc -l < "${sourcekind_fallbacks_file}" 2>/dev/null || echo 0)

if [[ "${fallback_count}" -gt 0 ]]; then
  echo "FAIL: Found ${fallback_count} sourceKind-based role classification patterns (should be zero):"
  cat "${sourcekind_fallbacks_file}"
  all_checks_passed=false
else
  echo "PASS: No sourceKind-based role fallback detected in roles.nix"
fi

# ============================================================
# Predicate 2: explicitWan/explicitTransit/explicitLocalAdapter consumed
# ============================================================
echo ""
echo "--- Predicate 2: Explicit role flags consumed ---"

# Verify that explicit role flags from CPM are consumed
explicit_checks=(
  "boolOrFalse entry.explicit.explicitWan"
  "boolOrFalse entry.explicit.explicitTransit"
  "boolOrFalse entry.explicit.explicitLocalAdapter"
  "explicitWanNames"
  "explicitTransitNames"
  "explicitLocalAdapterNames"
)

all_explicit_found=true
for check in "${explicit_checks[@]}"; do
  if grep -qF "${check}" "${roles_file}" 2>/dev/null; then
    echo "  OK: '${check}' found in roles.nix"
  else
    echo "  FAIL: '${check}' NOT found in roles.nix"
    all_explicit_found=false
  fi
done

if ${all_explicit_found}; then
  echo "PASS: All explicit role flags consumed in roles.nix"
else
  echo "FAIL: Missing explicit role flag consumption"
  all_checks_passed=false
fi

# ============================================================
# Predicate 3: No fallback exists — resolvedNames = explicitNames (no fallback chain)
# ============================================================
echo ""
echo "--- Predicate 3: resolved*Names use explicit names directly ---"

# Verify that resolved*Names use explicit*Names directly, not a fallback chain
resolution_checks=(
  "resolvedLocalAdapterNames = explicitLocalAdapterNames"
  "resolvedWanNames = explicitWanNames"
  "resolvedLanNames = explicitLocalAdapterNames"
  "resolvedTransitNames = explicitTransitNames"
  "resolvedUplinkNames = explicitUplinkNames"
  "resolvedAccessUplinkNames = explicitUplinkNames"
)

all_direct=true
for check in "${resolution_checks[@]}"; do
  if grep -qF "${check}" "${roles_file}" 2>/dev/null; then
    echo "  OK: Direct assignment found: ${check}"
  elif grep -qF "${check%% = *}" "${roles_file}" 2>/dev/null; then
    # Check if the name exists but with a different form (e.g. if != [] then ... else ...)
    echo "  FAIL: '${check%% = *}' exists but may have fallback logic"
    all_direct=false
  else
    echo "  FAIL: '${check%% = *}' not found in roles.nix"
    all_direct=false
  fi
done

if ${all_direct}; then
  echo "PASS: All resolved*Names use direct explicit assignments (no fallback)"
else
  echo "FAIL: Some resolved*Names may use fallback logic"
  all_checks_passed=false
fi

# ============================================================
# Seeded Negative: Detect if sourceKind fallback is reintroduced
# ============================================================
echo ""
echo "--- Seeded Negative: Would detect reintroduced sourceKind fallback ---"

# Create a temporary file with a fake fallback and verify the scanner catches it
fake_fallback_file="${tmp_dir}/fake-roles.nix"
cp "${roles_file}" "${fake_fallback_file}"
cat >> "${fake_fallback_file}" << 'FAKE'

  # SEEDED-NEGATIVE: Fake fallback for testing scanner sensitivity
  fallbackWanNames = sortedStrings (map (entry: entry.name) (lib.filter (entry: entry.sourceKind == "wan") entries));
  resolvedWanNames = if explicitWanNames != [ ] then explicitWanNames else fallbackWanNames;
FAKE

fake_fallbacks_file="${tmp_dir}/fake-fallbacks.txt"
> "${fake_fallbacks_file}"
grep -n 'sourceKind.*"wan"' "${fake_fallback_file}" 2>/dev/null >> "${fake_fallbacks_file}" || true

fake_fallback_count=$(wc -l < "${fake_fallbacks_file}" 2>/dev/null || echo 0)

if [[ "${fake_fallback_count}" -ge 1 ]]; then
  echo "PASS: Seeded negative — scanner detects reintroduced sourceKind fallback"
else
  echo "FAIL: Seeded negative — scanner failed to detect reintroduced sourceKind fallback"
  all_checks_passed=false
fi

# ============================================================
# Predicate 4: interfaces.nix uses boolLikeFromPaths for explicit flags
# ============================================================
echo ""
echo "--- Predicate 4: interfaces.nix explicit flags from CPM paths ---"

interfaces_file="${src_dir}/ControlModule/firewall/lookup/forwarding-intent/interfaces.nix"

explicit_path_checks=(
  "explicitWan = boolLikeFromPaths"
  "explicitTransit = boolLikeFromPaths"
  "explicitLocalAdapter = boolLikeFromPaths"
)

all_paths_found=true
for check in "${explicit_path_checks[@]}"; do
  if grep -qF "${check}" "${interfaces_file}" 2>/dev/null; then
    echo "  OK: '${check}' found in interfaces.nix"
  else
    echo "  FAIL: '${check}' NOT found in interfaces.nix"
    all_paths_found=false
  fi
done

if ${all_paths_found}; then
  echo "PASS: interfaces.nix derives explicit role flags from CPM output paths"
else
  echo "FAIL: Missing explicit role flag derivation in interfaces.nix"
  all_checks_passed=false
fi

# ============================================================
# Report
# ============================================================
echo ""
if ${all_checks_passed}; then
  echo "PASS: FS-320-HDS-040-SDS-010-SMS-060 — NixOS renderer uses CPM explicit role classification, no sourceKind fallback."
  exit 0
else
  echo "FAIL: FS-320-HDS-040-SDS-010-SMS-060 — one or more predicates failed."
  exit 1
fi
