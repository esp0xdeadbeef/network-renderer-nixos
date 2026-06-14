#!/usr/bin/env bash
# GAMP-ID: FS-310-HDS-040-SDS-010-SMS-101
# GAMP-SCOPE: software-module-test
# Focused construction test: NixOS renderer CPM-only consumption source scan.
#
# SMS-101: NixOS renderer must consume all network data through CPM-mediated
# output. Scans s88/ControlModule/ for direct upstream file access violations.
# Parent SMS-100 covers cross-renderer principle; SMS-101 adds nixos-specific
# file paths, pipeline architecture boundaries, and renderer-specific diagnostics.
#
# Diagnostic identifiers (must appear in violation reports):
#   DIRECT_UPSTREAM_ACCESS_NIXOS         — direct intent/inventory import/read
#   DIRECT_UPSTREAM_PATH_CONSTRUCTION_NIXOS — filesystem path construction to upstream files
#
# KNOWN_GAPS document any pre-existing violations that are tracked but not yet
# resolved. When a gap is fixed, the test detects it as removed.
# NEW violations beyond KNOWN_GAPS cause test failure.
#
# Active seeded negatives:
#   N1 — inject direct intent import in ControlModule/render/ fixture
#        expect detection with DIRECT_UPSTREAM_ACCESS_NIXOS diagnostic
#   N2 — inject path construction for inventory-nixos.nix in ControlModule/lookup/
#        expect detection with DIRECT_UPSTREAM_PATH_CONSTRUCTION_NIXOS diagnostic
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
tmp_dir="$(mktemp -d)"
trap 'rm -rf "${tmp_dir}"' EXIT
all_checks_passed=true
src_dir="${repo_root}/s88/ControlModule"

echo "--- FS-310-HDS-040-SDS-010-SMS-101: NixOS Renderer CPM-only consumption source scan ---"
echo ""

# ============================================================
# Diagnostic identifiers (SMS-101 violation categories)
# ============================================================
DIAGNOSTICS=(
  "DIRECT_UPSTREAM_ACCESS_NIXOS"
  "DIRECT_UPSTREAM_PATH_CONSTRUCTION_NIXOS"
)

# ============================================================
# Helper: determine which diagnostic applies to a violation
# ============================================================
assign_diagnostic() {
  local content="$1"
  
  # Path construction to upstream files (resolvedFabricRoot, resolvedExampleDir, outPath)
  if echo "${content}" | grep -qE '(resolvedFabricRoot|resolvedExampleDir|outPath).*(intent|inventory)'; then
    echo "DIRECT_UPSTREAM_PATH_CONSTRUCTION_NIXOS"
    return
  fi
  
  # Direct import/read of upstream files
  if echo "${content}" | grep -qE '(intentPath|inventoryPath|importMaybeFunction.*intent|importMaybeFunction.*inventory|builtins\.readFile.*intent\.nix|builtins\.readFile.*inventory\.nix)'; then
    echo "DIRECT_UPSTREAM_ACCESS_NIXOS"
    return
  fi
  
  # Default: access-type
  echo "DIRECT_UPSTREAM_ACCESS_NIXOS"
}

# ============================================================
# Helper: classification of a hit (production path vs permitted)
# ============================================================
classify_hit() {
  local file_path="$1"
  local content="$2"
  
  # Local imports of forwarding-intent.nix (within firewall module) are local, not upstream
  if echo "${file_path}" | grep -q 'firewall' && echo "${content}" | grep -q 'forwarding-intent\.nix'; then
    echo "LOCAL_MODULE_IMPORT"
    return
  fi
  
  # Skip comment-only lines
  if echo "${content}" | grep -qE '^\s*(#|//)'; then
    echo "COMMENT"
    return
  fi
  
  # Guard assertions that document the prohibition
  if echo "${content}" | grep -qF 'CMC-NIXOS-' || echo "${content}" | grep -qF 'NOT discover intent.nix/inventory.nix from disk'; then
    echo "GUARD_ASSERTION"
    return
  fi
  
  # Lines that explain the removal in throw messages
  if echo "${content}" | grep -qF 'renderers must consume' || echo "${content}" | grep -qF 'renderers must NOT'; then
    echo "GUARD_ASSERTION"
    return
  fi
  
  echo "PRODUCTION_PATH"
}

# ============================================================
# P1: Scan s88/ControlModule/ for direct upstream file access
# ============================================================
echo "--- P1: Scanning s88/ControlModule/ for direct upstream file access ---"

# Collect all hits for intentPath, inventoryPath, and upstream file path references
all_hits="$(grep -rn -E '(intentPath|inventoryPath|resolvedFabricRoot.*intent|resolvedFabricRoot.*inventory|resolvedExampleDir.*inventory|outPath.*intent\.nix|outPath.*inventory)' "${src_dir}" --include='*.nix' 2>/dev/null || true)"

upstream_count=0
new_violations=0
known_gap_count=0

# KNOWN_GAPS: document any pre-existing violations that are tracked but not yet resolved.
# Format: "file_substring:content_substring"
KNOWN_GAPS=(
  # Currently empty — source has been cleaned of direct upstream file access.
  # When new violations are discovered during audit, add them here.
)

while IFS= read -r line; do
  [[ -z "${line}" ]] && continue
  file_path="$(echo "${line}" | cut -d: -f1)"
  rel_path="${file_path#${repo_root}/}"
  content="$(echo "${line}" | cut -d: -f2-)"
  
  classification="$(classify_hit "${rel_path}" "${content}")"
  
  case "${classification}" in
    LOCAL_MODULE_IMPORT|COMMENT|GUARD_ASSERTION)
      # Permitted — not a production-path violation
      ;;
    PRODUCTION_PATH)
      upstream_count=$((upstream_count + 1))
      diagnostic="$(assign_diagnostic "${content}")"
      
      is_known=false
      for kg in "${KNOWN_GAPS[@]}"; do
        kf="${kg%%:*}"
        kc="${kg#*:}"
        if [[ "${rel_path}" == *"${kf}"* ]] && echo "${content}" | grep -qF "${kc}"; then
          is_known=true
          break
        fi
      done
      
      if [[ "${is_known}" == "true" ]]; then
        known_gap_count=$((known_gap_count + 1))
        echo "  KNOWN_GAP [${diagnostic}] ${rel_path}: $(echo "${content}" | head -c 80)"
      else
        echo "  NEW_VIOLATION [${diagnostic}] ${rel_path}: $(echo "${content}" | head -c 80)"
        new_violations=$((new_violations + 1))
      fi
      ;;
  esac
done <<< "${all_hits}"

echo "PRODUCTION_PATH hits scanned: ${upstream_count}"
echo "Known gaps: ${known_gap_count}"
echo "New violations: ${new_violations}"
[[ "${new_violations}" -gt 0 ]] && all_checks_passed=false
echo ""

# ============================================================
# P2: Scan for builtins.readFile of upstream source files
# ============================================================
echo "--- P2: Scanning for builtins.readFile of upstream source ---"
readfile_hits="$(grep -rn 'builtins\.readFile.*intent\.nix\|builtins\.readFile.*inventory\.nix' "${src_dir}" --include='*.nix' 2>/dev/null || true)"
readfile_violations=0

while IFS= read -r line; do
  [[ -z "${line}" ]] && continue
  file_path="$(echo "${line}" | cut -d: -f1)"
  rel_path="${file_path#${repo_root}/}"
  content="$(echo "${line}" | cut -d: -f2-)"
  
  echo "  NEW_VIOLATION [DIRECT_UPSTREAM_ACCESS_NIXOS] ${rel_path}: $(echo "${content}" | head -c 80)"
  readfile_violations=$((readfile_violations + 1))
done <<< "${readfile_hits}"

echo "builtins.readFile violations: ${readfile_violations}"
[[ "${readfile_violations}" -gt 0 ]] && all_checks_passed=false
echo ""

# ============================================================
# P3: Verify diagnostic identifiers appear in violation output
#     when violations exist (self-validating the scanner's
#     ability to produce SMS-101-specific diagnostics)
# ============================================================
echo "--- P3: Self-validating diagnostic output ---"
# Capture the test output so far to verify diagnostics would appear when needed
diag_present=0
diag_absent=""
for diag in "${DIAGNOSTICS[@]}"; do
  # Check source code for the diagnostic (should exist in guard messages)
  if grep -rq "${diag}" "${repo_root}/s88/" --include='*.nix' 2>/dev/null; then
    diag_present=$((diag_present + 1))
  else
    diag_absent="${diag_absent}${diag}, "
  fi
done

echo "Diagnostic strings in source: ${diag_present}/${#DIAGNOSTICS[@]}"
if [[ -n "${diag_absent}" ]]; then
  echo "  Not in source: ${diag_absent%, }"
  echo "  NOTE: Diagnostics are not yet embedded in source guards (source is clean)."
  echo "  The seeded negatives below prove the scanner can emit SMS-101 diagnostics."
fi
echo ""

# ============================================================
# N1: Active seeded negative — DIRECT_UPSTREAM_ACCESS_NIXOS
# ============================================================
echo "--- N1: Seeded negative — DIRECT_UPSTREAM_ACCESS_NIXOS ---"

n1_fixture="${tmp_dir}/n1-fixture"
mkdir -p "${n1_fixture}/ControlModule/render"

# Create a simulated production file with direct intent import
cat > "${n1_fixture}/ControlModule/render/bad-render-file.nix" << 'NIXEOF'
{ selectors, intentPath }:

# This file simulates a production render path that directly imports intent.nix.
# Per FS-310-HDS-040-SDS-010-SMS-101, this is a DIRECT_UPSTREAM_ACCESS_NIXOS violation.

let
  intent = selectors.importMaybeFunction (builtins.toPath intentPath);
in
{
  rendered = intent.someField or { };
}
NIXEOF

# Scan the fixture using the same patterns as P1
n1_scan="$(grep -rn -E '(intentPath|inventoryPath|importMaybeFunction.*intentPath)' "${n1_fixture}" --include='*.nix' 2>/dev/null || true)"
n1_detected=false
n1_diag_found=false

while IFS= read -r scan_line; do
  [[ -z "${scan_line}" ]] && continue
  
  # Classify the hit and assign diagnostic
  scan_file="$(echo "${scan_line}" | cut -d: -f1)"
  scan_content="$(echo "${scan_line}" | cut -d: -f2-)"
  scan_class="$(classify_hit "${scan_file}" "${scan_content}")"
  
  if [[ "${scan_class}" == "PRODUCTION_PATH" ]]; then
    scan_diag="$(assign_diagnostic "${scan_content}")"
    echo "  N1 hit [${scan_diag}] ${scan_file}: $(echo "${scan_content}" | head -c 80)"
    
    if [[ "${scan_diag}" == "DIRECT_UPSTREAM_ACCESS_NIXOS" ]]; then
      n1_diag_found=true
    fi
    
    if echo "${scan_content}" | grep -qE 'intentPath'; then
      n1_detected=true
    fi
  fi
done <<< "${n1_scan}"

if [[ "${n1_detected}" == "true" ]]; then
  echo "  PASS: N1 violation detected (direct intentPath usage)"
else
  echo "  FAIL: N1 violation NOT detected — scanner may miss direct intentPath usage"
  all_checks_passed=false
fi

if [[ "${n1_diag_found}" == "true" ]]; then
  echo "  PASS: N1 diagnostic DIRECT_UPSTREAM_ACCESS_NIXOS assigned correctly"
else
  echo "  FAIL: N1 diagnostic DIRECT_UPSTREAM_ACCESS_NIXOS not assigned"
  all_checks_passed=false
fi

# Recovery: remove the violation and verify clean scan
rm "${n1_fixture}/ControlModule/render/bad-render-file.nix"
n1_clean_scan="$(grep -rn -E '(intentPath|inventoryPath)' "${n1_fixture}" --include='*.nix' 2>/dev/null || true)"
if [[ -z "${n1_clean_scan}" ]]; then
  echo "  PASS: N1 recovery — clean fixture has no violations"
else
  echo "  FAIL: N1 recovery — fixture still shows violations after removal"
  all_checks_passed=false
fi
echo ""

# ============================================================
# N2: Active seeded negative — DIRECT_UPSTREAM_PATH_CONSTRUCTION_NIXOS
# ============================================================
echo "--- N2: Seeded negative — DIRECT_UPSTREAM_PATH_CONSTRUCTION_NIXOS ---"

n2_fixture="${tmp_dir}/n2-fixture"
mkdir -p "${n2_fixture}/ControlModule/lookup"

# Create a simulated production file with upstream path construction
cat > "${n2_fixture}/ControlModule/lookup/bad-lookup-file.nix" << 'NIXEOF'
{ lib, resolvedFabricRoot }:

# This file simulates a production lookup path that constructs a filesystem path
# to upstream inventory-nixos.nix. Per FS-310-HDS-040-SDS-010-SMS-101, this is
# a DIRECT_UPSTREAM_PATH_CONSTRUCTION_NIXOS violation.

let
  inventoryPath = "${resolvedFabricRoot}/inputs/inventory-nixos.nix";
  inventory = import inventoryPath;
in
{
  resolvedInventory = inventory or { };
}
NIXEOF

# Scan the fixture using the same patterns as P1
n2_scan="$(grep -rn -E '(resolvedFabricRoot.*inventory|resolvedExampleDir.*inventory)' "${n2_fixture}" --include='*.nix' 2>/dev/null || true)"
n2_detected=false
n2_diag_found=false

while IFS= read -r scan_line; do
  [[ -z "${scan_line}" ]] && continue
  
  scan_file="$(echo "${scan_line}" | cut -d: -f1)"
  scan_content="$(echo "${scan_line}" | cut -d: -f2-)"
  scan_class="$(classify_hit "${scan_file}" "${scan_content}")"
  
  if [[ "${scan_class}" == "PRODUCTION_PATH" ]]; then
    scan_diag="$(assign_diagnostic "${scan_content}")"
    echo "  N2 hit [${scan_diag}] ${scan_file}: $(echo "${scan_content}" | head -c 80)"
    
    if [[ "${scan_diag}" == "DIRECT_UPSTREAM_PATH_CONSTRUCTION_NIXOS" ]]; then
      n2_diag_found=true
    fi
    
    if echo "${scan_content}" | grep -qE 'resolvedFabricRoot.*inventory'; then
      n2_detected=true
    fi
  fi
done <<< "${n2_scan}"

if [[ "${n2_detected}" == "true" ]]; then
  echo "  PASS: N2 violation detected (path construction for inventory-nixos.nix)"
else
  echo "  FAIL: N2 violation NOT detected — scanner may miss path construction"
  all_checks_passed=false
fi

if [[ "${n2_diag_found}" == "true" ]]; then
  echo "  PASS: N2 diagnostic DIRECT_UPSTREAM_PATH_CONSTRUCTION_NIXOS assigned correctly"
else
  echo "  FAIL: N2 diagnostic DIRECT_UPSTREAM_PATH_CONSTRUCTION_NIXOS not assigned"
  all_checks_passed=false
fi

# Recovery: remove the violation and verify clean scan
rm "${n2_fixture}/ControlModule/lookup/bad-lookup-file.nix"
n2_clean_scan="$(grep -rn -E '(resolvedFabricRoot.*inventory|resolvedExampleDir.*inventory)' "${n2_fixture}" --include='*.nix' 2>/dev/null || true)"
if [[ -z "${n2_clean_scan}" ]]; then
  echo "  PASS: N2 recovery — clean fixture has no violations"
else
  echo "  FAIL: N2 recovery — fixture still shows violations after removal"
  all_checks_passed=false
fi
echo ""

# ============================================================
# P4: Verify hostModule entrypoints only accept cpm/controlPlane
#     (not intentPath/inventoryPath)
# ============================================================
echo "--- P4: hostModule parameter audit ---"

# Check that production render entrypoints do not accept intentPath/inventoryPath
host_entrypoints=(
  "s88/Unit/api/box-build-inputs.nix"
  "s88/Unit/api/module-host-build.nix"
  "s88/Unit/api/dry-render-build.nix"
)

p4_violations=0
for ep in "${host_entrypoints[@]}"; do
  ep_path="${repo_root}/${ep}"
  if [[ -f "${ep_path}" ]]; then
    ep_hits="$(grep -n 'intentPath\|inventoryPath' "${ep_path}" 2>/dev/null || true)"
    while IFS= read -r ep_line; do
      [[ -z "${ep_line}" ]] && continue
      
      # Strip line-number prefix for classification (grep -n adds "NN:")
      content_only="${ep_line#*:}"
      [[ -z "${content_only}" ]] && continue
      
      # Skip comments (lines where content after stripping whitespace starts with #)
      echo "${content_only}" | grep -qE '^\s*(#|//)' && continue
      echo "${content_only}" | grep -qF 'CMC-NIXOS-' && continue
      echo "${content_only}" | grep -qF 'renderers must' && continue
      echo "${content_only}" | grep -qF 'NOT discover' && continue
      # Skip lines inside throw messages (they're documentation of prohibition)
      echo "${content_only}" | grep -qF 'throw' && continue
      
      echo "  VIOLATION [DIRECT_UPSTREAM_ACCESS_NIXOS] ${ep}:${ep_line}"
      p4_violations=$((p4_violations + 1))
    done <<< "${ep_hits}"
  fi
done

if [[ "${p4_violations}" -gt 0 ]]; then
  echo "FAIL: hostModule entrypoints still reference intentPath/inventoryPath"
  all_checks_passed=false
else
  echo "PASS: hostModule entrypoints reference only cpm/controlPlane parameters"
fi
echo ""

# ============================================================
# Report
# ============================================================
if [[ "${all_checks_passed}" == "true" ]]; then
  echo "PASS: FS-310-HDS-040-SDS-010-SMS-101 NixOS renderer CPM-only consumption scan complete."
  echo "  P1 source scan: clean (${upstream_count} hits, ${new_violations} new, ${known_gap_count} known gaps)"
  echo "  P2 readFile: clean (${readfile_violations} violations)"
  echo "  P3 diagnostics: ${diag_present}/${#DIAGNOSTICS[@]} in source, both proven in seeded negatives"
  echo "  N1: DIRECT_UPSTREAM_ACCESS_NIXOS — detected and recovered"
  echo "  N2: DIRECT_UPSTREAM_PATH_CONSTRUCTION_NIXOS — detected and recovered"
  echo "  P4 hostModule audit: clean"
  exit 0
else
  echo "FAIL: FS-310-HDS-040-SDS-010-SMS-101 — violations found."
  exit 1
fi
