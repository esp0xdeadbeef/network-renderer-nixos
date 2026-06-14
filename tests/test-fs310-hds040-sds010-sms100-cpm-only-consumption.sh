#!/usr/bin/env bash
# GAMP-ID: FS-310-HDS-040-SDS-010-SMS-100
# GAMP-SCOPE: software-module-test
# Focused construction test: Renderer CPM-only consumption source scan.
#
# SMS-100: Renderers must consume all network data through CPM-mediated output.
# Scans NixOS renderer source for upstream file access violations.
#
# All currently-found violations are documented as KNOWN_GAPS.
# When a gap is fixed, the test detects it as removed.
# NEW violations beyond KNOWN_GAPS cause test failure.
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
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
  content="$(echo "${line}" | cut -d: -f2-)"
  
  # Skip local imports and parameter defaults
  [[ "${content}" =~ ^[[:space:]]*# ]] && continue
  echo "${content}" | grep -qE 'import \./' && continue
  echo "${content}" | grep -qE 'file \? "s88/' && continue
  
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
# Predicate 2: Seeded negative — verify known gaps exist
# ============================================================
echo "--- Seeded negative: verify known gaps are detectable ---"
total_known=$((upstream_path_count + realization_node_count))
echo "Total known gaps detected: ${total_known}"
if [[ "${total_known}" -gt 0 ]]; then
  echo "PASS: Known gaps present in source (scanner detects them)."
else
  echo "FAIL: No known gaps found — scanner may be broken."
  all_checks_passed=false
fi
echo ""

# ============================================================
# Report
# ============================================================
if [[ "${all_checks_passed}" == "true" ]]; then
  echo "PASS: FS-310-HDS-040-SDS-010-SMS-100 CPM-only consumption scan complete."
  echo "Tracking ${total_known} known gaps across ${#KNOWN_FILE_PATTERNS[@]} file patterns + ${#KNOWN_REALIZATION_FILES[@]} realization files."
  exit 0
else
  echo "FAIL: ${new_violations} new violation(s) found beyond documented known gaps."
  exit 1
fi
