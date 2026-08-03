#!/usr/bin/env bash
# GAMP-ID: FS-310-HDS-010-SDS-010-SMS-120
# GAMP-SCOPE: software-module-test
# Focused construction test: NixOS renderer source scan for builtins.match
# naming-inference patterns. Scans all renderer .nix source under s88/,
# classifies each builtins.match as platform-validation (permitted) or
# naming-inference (rejected). Fails if any naming-inference patterns are found.
# SMS-120: Renderers must not derive network meaning from name patterns.
# All classification must use explicit CPM metadata fields, not string matching.
set -euo pipefail

repo_root="${SMS_TEST_REPO_ROOT:-$(git -C "$(dirname "${BASH_SOURCE[0]}")" rev-parse --show-toplevel)}"
source "${repo_root}/tests/lib/direct-test-guard.sh" 2>/dev/null || true

tmp_dir="$(mktemp -d)"
trap 'rm -rf "${tmp_dir}"' EXIT

all_checks_passed=true
src_dir="${repo_root}/s88"

echo "--- FS-310-HDS-010-SDS-010-SMS-120: NixOS renderer source scan for naming-inference ---"
echo ""

# ============================================================
# KNOWN PERMITTED builtins.match regex patterns
# (platform-validation / format checks, NOT naming inference)
# ============================================================
PERMITTED_PATTERNS=(
  # --- IPv6 address detection (colon presence) ---
  '".*:.*"'

  # --- CIDR prefix extraction (bgp-services) ---
  '"([^/]+)/?.*"'

  # --- Linux interface name char validation ---
  '"[A-Za-z0-9_.-]"'
  '"[A-Za-z0-9_.-]+"'
  '"^[A-Za-z0-9_.-]{1,15}$"'

  # --- Predictable kernel interface name detection (rename purposes) ---
  '"eth[0-9]+"'
  '"ens[0-9]+"'
  '"eno[0-9]+"'
  '"enp[0-9s.]+"'
  '"enx[0-9a-fA-F]+"'

  # --- Secret-key redaction in provenance (platform integrity, not policy) ---
  '".*${needle}.*"'
)

# ============================================================
# Classification function
# ============================================================
classify_line() {
  local file="$1" line_num="$2" content="$3"

  # Extract the string between the first pair of double quotes after "builtins.match"
  local pattern
  pattern=$(echo "${content}" | sed -n 's/.*builtins\.match *"\([^"]*\)".*/\1/p' | head -1)

  if [[ -z "${pattern}" ]]; then
    return 0  # Can't extract, skip
  fi

  # Reconstruct the full quoted form for comparison
  local full_pattern="\"${pattern}\""

  # Check against permitted set
  local allowed
  for allowed in "${PERMITTED_PATTERNS[@]}"; do
    if [[ "${full_pattern}" == "${allowed}" ]]; then
      return 0  # Permitted — platform validation
    fi
  done

  # Not in permitted set → NAMING_INFERENCE
  echo "  NAMING_INFERENCE: ${file}:${line_num}: ${full_pattern}"
  return 1
}

# ============================================================
# Scan all renderer source .nix files under s88/ for builtins.match
# ============================================================
echo "SCAN: Searching all NixOS renderer .nix source for builtins.match..."
echo ""

violations=0
scanned_count=0

while IFS= read -r line; do
  [[ -z "${line}" ]] && continue
  file=$(echo "${line}" | cut -d: -f1)
  line_num=$(echo "${line}" | cut -d: -f2)
  content=$(echo "${line}" | cut -d: -f3-)

  scanned_count=$((scanned_count + 1))
  classify_line "${file}" "${line_num}" "${content}" || violations=$((violations + 1))
done < <(grep -rn 'builtins\.match' "${src_dir}/" --include='*.nix' 2>/dev/null || true)

echo "Scanned ${scanned_count} builtins.match hits across NixOS renderer source."
echo ""

# ============================================================
# Check results
# ============================================================
if [[ "${violations}" -gt 0 ]]; then
  echo "FAIL: ${violations} naming-inference builtins.match pattern(s) found."
  echo "  SMS-120 requires all classification to use explicit CPM metadata fields."
  echo "  Replace name-pattern matches with structural metadata from the"
  echo "  canonical realization bundle (attach.vlan, attach.parentUplink, etc.)."
  echo ""
  all_checks_passed=false
else
  echo "PASS: 0 naming-inference patterns found in NixOS renderer source."
  echo "  All builtins.match uses are platform-validation"
  echo "  (IP format, interface name constraints, kernel rename detection,"
  echo "  provenance redaction)."
  echo ""
fi

# ============================================================
# Seeded negative: inject fake .nix with naming-inference patterns
# covering the renderer-specific naming categories from SMS-120
# §Module Failure Conditions (transit VLAN extraction, selector
# prefix, interface role from name, renderer technology names).
# ============================================================
echo "--- FS-310-HDS-010-SDS-010-SMS-120: Seeded negative (renderer) ---"
echo ""

fake_nix="${tmp_dir}/fake-renderer-naming-inference.nix"
cat > "${fake_nix}" <<'NIXEOF'
# Seeded negative for SMS-120 (renderer side): contains intentional
# naming-inference patterns that renderers must not use.
# All should be flagged as NAMING_INFERENCE.
{
  # Transit VLAN extraction from bridge name pattern (e.g., tr42 → VLAN 42)
  parseVlanFromName = bridgeName:
    builtins.match "tr[0-9]+" bridgeName != null;

  # Selector rule classification from relation ID prefix
  isSelectorRule = rule:
    builtins.match "selector-.*" (rule.relationId or "") != null;

  # Interface role from name substring
  isManagementUplink = uplinkName:
    builtins.match ".*management.*" uplinkName != null;

  # Host-facing from name substring
  isHostFacing = iface:
    builtins.match ".*host-facing.*" (iface.name or "") != null;

  # Renderer technology name in renderer source
  classifyByTechName = iface:
    builtins.match ".*wireguard.*" (iface.backingRef or "") != null;
}
NIXEOF

neg_violations=0
while IFS= read -r line; do
  [[ -z "${line}" ]] && continue
  file=$(echo "${line}" | cut -d: -f1)
  line_num=$(echo "${line}" | cut -d: -f2)
  content=$(echo "${line}" | cut -d: -f3-)
  classify_line "${file}" "${line_num}" "${content}" || neg_violations=$((neg_violations + 1))
done < <(grep -Hrn 'builtins\.match' "${fake_nix}" 2>/dev/null || true)

if [[ "${neg_violations}" -ge 5 ]]; then
  echo "  Seeded negative PASS: ${neg_violations} injected violations correctly detected."
  echo "  Prohibited patterns caught:"
  echo "    - tr[0-9]+ (transit VLAN extraction from bridge name)"
  echo "    - selector-.* (selector rule classification from relation ID)"
  echo "    - .*management.* (interface role from name substring)"
  echo "    - .*host-facing.* (host-facing from name substring)"
  echo "    - .*wireguard.* (renderer technology name matching)"
else
  echo "  Seeded negative FAIL: expected >=5 detections, got ${neg_violations}"
  echo "  The classification function is not detecting naming-inference patterns."
  echo "  Check: PERMITTED_PATTERNS array, sed extraction, and comparison logic."
  all_checks_passed=false
fi
echo ""

# ============================================================
# Renderer-specific: verify transit-bridges.nix no longer has
# parseTransitVlan or builtins.match "tr[0-9]+" in source.
# ============================================================
echo "--- FS-310-HDS-010-SDS-010-SMS-120: Transit-bridges source check ---"
echo ""

transit_bridges="${repo_root}/s88/EquipmentModule/physical/transit-bridges.nix"
if [[ -f "${transit_bridges}" ]]; then
  if grep -q 'parseTransitVlan\|builtins\.match.*tr\[0-9\]' "${transit_bridges}" 2>/dev/null; then
    echo "  FAIL: transit-bridges.nix still contains parseTransitVlan or tr[0-9]+ name matching"
    echo "  SMS-120 requires VLAN to come from explicit attach.vlan metadata, not bridge name."
    all_checks_passed=false
  else
    echo "  PASS: transit-bridges.nix does not contain parseTransitVlan or tr[0-9]+ matching."
    echo "  VLAN extraction now uses explicit attach.vlan metadata from CPM inventory."
  fi
else
  echo "  SKIP: transit-bridges.nix not found at ${transit_bridges}"
fi
echo ""

# ============================================================
# Final
# ============================================================
if [[ "${all_checks_passed}" == "true" ]]; then
  echo "PASS FS-310-HDS-010-SDS-010-SMS-120 (renderer)"
  exit 0
else
  echo "FAIL FS-310-HDS-010-SDS-010-SMS-120 (renderer)"
  exit 1
fi
