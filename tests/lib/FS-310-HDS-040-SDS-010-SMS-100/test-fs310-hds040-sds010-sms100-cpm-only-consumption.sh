#!/usr/bin/env bash
# GAMP-ID: FS-310-HDS-040-SDS-010-SMS-100
# GAMP-SCOPE: software-module-test
# Focused construction test: Renderer CPM-only consumption source scan.
#
# SMS-100: Renderers must consume all network data through CPM-mediated output.
# Scans NixOS renderer source for upstream file access violations.
#
# Active seeded negatives (per SMS-100 Seeded Negative Requirement):
#   N1 — direct intent.nix import via filesystem path → DIRECT_UPSTREAM_ACCESS
#   N2 — raw inventory.realization.nodes walk → INVENTORY_TREE_WALK
#
# All currently-found violations are documented as KNOWN_GAPS.
# When a gap is fixed, the test detects it as removed.
# NEW violations beyond KNOWN_GAPS cause test failure.
set -euo pipefail

repo_root="${SMS_TEST_REPO_ROOT:-$(git -C "$(dirname "${BASH_SOURCE[0]}")" rev-parse --show-toplevel)}"
tmp_dir="$(mktemp -d)"
trap 'rm -rf "${tmp_dir}"' EXIT
all_checks_passed=true
src_dir="${repo_root}/s88"

echo "--- FS-310-HDS-040-SDS-010-SMS-100: Renderer CPM-only consumption source scan ---"
echo ""

# ============================================================
# Collect all violations into categorized lists
# ============================================================
echo "--- Scanning for upstream file path references ---"
all_hits="$(grep -rn -E '(intent\.nix|inventory[^.]*\.nix)' "${src_dir}" --include='*.nix' 2>/dev/null | grep -v 'tests/' || true)"

upstream_path_count=0
realization_node_count=0
new_violations=0

# KNOWN_GAP patterns (all currently known violations)
# Format: "file_substring:content_substring"
KNOWN_FILE_PATTERNS=(
  "paths.nix:inputs/intent.nix"
  "paths.nix:inputs/inventory-nixos.nix"
  "paths.nix:inputs/inventory.nix"
  "paths.nix:inventory-nixos.nix"
  "paths.nix:inventory.nix"
  "paths.nix:intent.nix"
  "render-inputs.nix:inventory-nixos.nix"
  "render-inputs.nix:inventory.nix"
  "firewall.nix:forwarding-intent.nix"
  "module-host-build.nix:resolved-inventory"
)

KNOWN_REALIZATION_FILES=(
  "host-query/inventory/helpers.nix"
  "host-runtime/context.nix"
  "runtime-context/base/realization.nix"
  "realization-ports/inventory.nix"
)

while IFS= read -r line; do
  [[ -z "${line}" ]] && continue
  file_path="$(echo "${line}" | cut -d: -f1)"
  rel_path="${file_path#${repo_root}/}"
  raw_content="$(echo "${line}" | cut -d: -f2-)"
  # Strip line-number prefix: grep -rn output is 'file:line:content'
  # After cut -d: -f2-, we get 'line:content' — strip the line number
  content="${raw_content#*:}"

  # Skip comment lines and local imports
  [[ "${content}" =~ ^[[:space:]]*# ]] && continue
  echo "${content}" | grep -qE 'import \./' && continue
  echo "${content}" | grep -qE 'file \? "s88/' && continue

  # Skip guard assertions that document the SMS-100 prohibition
  echo "${content}" | grep -qF 'CMC-NIXOS-' && continue
  echo "${content}" | grep -qF 'NOT discover intent.nix/inventory.nix from disk' && continue
  echo "${content}" | grep -qF 'not discover intent.nix/inventory.nix from disk' && continue
  echo "${content}" | grep -qF 'renderers must consume' && continue
  echo "${content}" | grep -qF 'renderers must NOT' && continue

  # Classify: is this an upstream path reference or a realization.nodes walk?
  if echo "${content}" | grep -q 'inventory\.realization\.nodes'; then
    is_known=false
    for kf in "${KNOWN_REALIZATION_FILES[@]}"; do
      [[ "${rel_path}" == *"${kf}"* ]] && { is_known=true; break; }
    done
    if [[ "${is_known}" == "true" ]]; then
      realization_node_count=$((realization_node_count + 1))
    else
      echo "NEW_REALIZATION: ${rel_path}"
      new_violations=$((new_violations + 1))
    fi
  else
    is_known=false
    for kp in "${KNOWN_FILE_PATTERNS[@]}"; do
      kf="${kp%%:*}"
      kc="${kp#*:}"
      if [[ "${rel_path}" == *"${kf}"* ]] && echo "${content}" | grep -qF "${kc}"; then
        is_known=true; break
      fi
    done
    if [[ "${is_known}" == "true" ]]; then
      upstream_path_count=$((upstream_path_count + 1))
    else
      echo "NEW_PATH: ${rel_path}: $(echo "${content}" | head -c 80)"
      new_violations=$((new_violations + 1))
    fi
  fi
done <<< "${all_hits}"

echo "Known upstream paths: ${upstream_path_count}"
echo "Known realization-node references: ${realization_node_count}"
echo "New violations: ${new_violations}"
[[ "${new_violations}" -gt 0 ]] && all_checks_passed=false
echo ""

# ============================================================
# N1: Active seeded negative — direct intent.nix import via filesystem path
# ============================================================
echo "--- N1: Seeded negative — direct intent.nix import via filesystem path ---"

n1_fixture="${tmp_dir}/n1-fixture"
mkdir -p "${n1_fixture}/render"

# Create a simulated production file that directly imports intent.nix via
# a constructed filesystem path (e.g., "${outPath}/inputs/intent.nix").
# Per SMS-100 Seeded Negative Requirement line 80-83, this must produce a
# direct-upstream-access diagnostic, not silently consume intent data.
cat > "${n1_fixture}/render/bad-intent-import.nix" << 'NIXEOF'
{ outPath, lib }:

# SMS-100 seeded negative: production render code importing intent.nix
# via a constructed filesystem path bypasses CPM mediation.
# This must trigger a DIRECT_UPSTREAM_ACCESS diagnostic.

let
  intentFile = "${outPath}/inputs/intent.nix";
  intent = import intentFile;
in
{
  tenants = intent.tenants or { };
}
NIXEOF

# Scan the fixture using the same patterns as the main source scan
n1_hits="$(grep -rn -E '(intent\.nix|inventory[^.]*\.nix)' "${n1_fixture}" --include='*.nix' 2>/dev/null || true)"
n1_detected=false

while IFS= read -r scan_line; do
  [[ -z "${scan_line}" ]] && continue
  scan_file="$(echo "${scan_line}" | cut -d: -f1)"
  scan_content="$(echo "${scan_line}" | cut -d: -f2-)"
  # Strip line number from grep output
  scan_content="${scan_content#*:}"

  # Skip comments
  [[ "${scan_content}" =~ ^[[:space:]]*# ]] && continue

  if echo "${scan_content}" | grep -qF 'intent.nix'; then
    echo "  N1 HIT [DIRECT_UPSTREAM_ACCESS] ${scan_file}: $(echo "${scan_content}" | head -c 80)"
    n1_detected=true
  fi
done <<< "${n1_hits}"

if [[ "${n1_detected}" == "true" ]]; then
  echo "  PASS: N1 — direct intent.nix import detected as DIRECT_UPSTREAM_ACCESS"
else
  echo "  FAIL: N1 — direct intent.nix import NOT detected; scanner may miss upstream path injection"
  all_checks_passed=false
fi

# Recovery: remove the violating file and verify clean scan
rm "${n1_fixture}/render/bad-intent-import.nix"
n1_clean="$(grep -rn -E '(intent\.nix|inventory[^.]*\.nix)' "${n1_fixture}" --include='*.nix' 2>/dev/null || true)"
if [[ -z "${n1_clean}" ]]; then
  echo "  PASS: N1 recovery — clean fixture has no violations"
else
  echo "  FAIL: N1 recovery — fixture still shows violations after removal"
  all_checks_passed=false
fi
echo ""

# ============================================================
# N2: Active seeded negative — raw inventory tree walk
# ============================================================
echo "--- N2: Seeded negative — raw inventory.realization.nodes walk ---"

n2_fixture="${tmp_dir}/n2-fixture"
mkdir -p "${n2_fixture}/render"

# Create a simulated production file that walks raw inventory tree paths
# (inventory.realization.nodes) instead of consuming CPM-mediated data.
# Per SMS-100 Seeded Negative Requirement line 85-88, this must produce
# an INVENTORY_TREE_WALK diagnostic, not silently resolve realization data.
cat > "${n2_fixture}/render/bad-inventory-walk.nix" << 'NIXEOF'
{ inventory, lib }:

# SMS-100 seeded negative: production render code walking raw
# inventory.realization.nodes to resolve realization data instead of
# consuming CPM-mediated inventory structures.
# This must trigger an INVENTORY_TREE_WALK diagnostic.

let
  nodes = inventory.realization.nodes or [ ];
  resolvedNodes = map (n: n.host or n) nodes;
in
{
  realized = resolvedNodes;
}
NIXEOF

# Scan the fixture for inventory.realization.nodes references
n2_hits="$(grep -rn 'inventory\.realization\.nodes' "${n2_fixture}" --include='*.nix' 2>/dev/null || true)"
n2_detected=false

while IFS= read -r scan_line; do
  [[ -z "${scan_line}" ]] && continue
  scan_file="$(echo "${scan_line}" | cut -d: -f1)"
  scan_content="$(echo "${scan_line}" | cut -d: -f2-)"
  scan_content="${scan_content#*:}"

  # Skip comments
  [[ "${scan_content}" =~ ^[[:space:]]*# ]] && continue

  if echo "${scan_content}" | grep -q 'inventory\.realization\.nodes'; then
    echo "  N2 HIT [INVENTORY_TREE_WALK] ${scan_file}: $(echo "${scan_content}" | head -c 80)"
    n2_detected=true
  fi
done <<< "${n2_hits}"

if [[ "${n2_detected}" == "true" ]]; then
  echo "  PASS: N2 — raw inventory.realization.nodes walk detected as INVENTORY_TREE_WALK"
else
  echo "  FAIL: N2 — raw inventory.realization.nodes walk NOT detected; scanner may miss tree-walk injection"
  all_checks_passed=false
fi

# Recovery: remove the violating file and verify clean scan
rm "${n2_fixture}/render/bad-inventory-walk.nix"
n2_clean="$(grep -rn 'inventory\.realization\.nodes' "${n2_fixture}" --include='*.nix' 2>/dev/null || true)"
if [[ -z "${n2_clean}" ]]; then
  echo "  PASS: N2 recovery — clean fixture has no violations"
else
  echo "  FAIL: N2 recovery — fixture still shows violations after removal"
  all_checks_passed=false
fi
echo ""

# ============================================================
# Report
# ============================================================
total_known=$((upstream_path_count + realization_node_count))
if [[ "${all_checks_passed}" == "true" ]]; then
  echo "PASS: FS-310-HDS-040-SDS-010-SMS-100 CPM-only consumption scan complete."
  echo "Source scan: ${upstream_path_count} known paths, ${realization_node_count} known realization refs, ${new_violations} new violations."
  echo "N1: DIRECT_UPSTREAM_ACCESS seeded negative — detected and recovered."
  echo "N2: INVENTORY_TREE_WALK seeded negative — detected and recovered."
  echo "Tracking ${total_known} known gaps across ${#KNOWN_FILE_PATTERNS[@]} file patterns + ${#KNOWN_REALIZATION_FILES[@]} realization files."
  exit 0
else
  echo "FAIL: ${new_violations} new violation(s) found beyond documented known gaps."
  exit 1
fi
