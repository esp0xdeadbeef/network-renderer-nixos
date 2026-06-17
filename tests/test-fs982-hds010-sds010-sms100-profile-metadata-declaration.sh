#!/usr/bin/env bash
# GAMP-ID: FS-982-HDS-010-SDS-010-SMS-100
# GAMP-SCOPE: software-module-test
# Focused construction test: Profile metadata field declaration — container enable.
#
# SMS-100: Every renderer role profile with a `container` attrset MUST declare
# an explicit `enable = true;` or `enable = false;` field. When a container
# attrset exists with sub-fields (advertise, enableEdgeServices) but omits
# `enable`, the module shall fail-closed: produce zero containers and emit
# diagnostic.profile-container-enable-missing naming the affected profile.
#
# Root cause: access.meta.nix had a container attrset with advertise and
# enableEdgeServices sub-fields but no enable field. lookup.nix correctly
# fail-closed via `or false` (per SMS-111), but zero containers were produced
# because the profile metadata was incomplete. Commit 410605d added
# enable = true; to access.meta.nix and a defaultContainer fallback in
# role-profiles.nix as belt-and-suspenders.
#
# Active seeded negatives:
#   SN1 — Container attrset with sub-fields but no enable → scanner detects
#          profile-container-enable-missing diagnostic
#   SN2 — Two profiles: one correct (enable=true), one missing enable → scanner
#          flags only the defective profile, correct profile passes
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
tmp_dir="$(mktemp -d)"
trap 'rm -rf "${tmp_dir}"' EXIT

failures=0

echo "--- FS-982-HDS-010-SDS-010-SMS-100: Profile metadata field declaration ---"
echo ""

# ============================================================
# Helper: scan a directory of .meta.nix files for container
# attrsets missing explicit enable field.
# Outputs one line per violation:
#   diagnostic.profile-container-enable-missing:<filename>
# ============================================================
scan_container_enable() {
  local scan_dir="$1"
  local out_file="$2"
  :> "${out_file}"

  if [[ ! -d "${scan_dir}" ]]; then
    return 0
  fi

  for meta_file in "${scan_dir}"/*.meta.nix; do
    [[ -f "${meta_file}" ]] || continue
    local basename
    basename="$(basename "${meta_file}")"

    # Does this file have a container attrset?
    if ! grep -q 'container\s*=' "${meta_file}"; then
      continue
    fi

    # Container attrset exists — must have explicit enable = true/false
    if ! grep -qE 'enable\s*=\s*(true|false)' "${meta_file}"; then
      echo "diagnostic.profile-container-enable-missing:${basename}" >> "${out_file}"
    fi
  done
}

# ============================================================
# Check 1: Happy path — scan real profiles
# All profiles with container attrsets must have explicit enable.
# Profiles without container attrsets are valid (SMS-100 line 25).
# ============================================================
echo "--- Check 1: Real profile container enable completeness ---"

profiles_dir="${repo_root}/s88/ControlModule/profiles"
happy_violations="${tmp_dir}/happy-violations.txt"
scan_container_enable "${profiles_dir}" "${happy_violations}"

happy_count=$(wc -l < "${happy_violations}" 2>/dev/null || echo 0)

if [[ "${happy_count}" -gt 0 ]]; then
  echo "FAIL: ${happy_count} profile(s) with container attrset missing enable:"
  cat "${happy_violations}"
  failures=$((failures + 1))
else
  echo "PASS: All profiles with container attrsets have explicit enable field"
fi
echo ""

# Count profiles without container attrsets (valid per SMS-100 line 25)
no_container=0
for meta_file in "${profiles_dir}"/*.meta.nix; do
  [[ -f "${meta_file}" ]] || continue
  if ! grep -q 'container\s*=' "${meta_file}"; then
    no_container=$((no_container + 1))
  fi
done
echo "INFO: ${no_container} profile(s) without container attrset (valid — no container surface)"
echo ""

# ============================================================
# Seeded Negative 1: Profile with container attrset containing
# sub-fields (advertise, enableEdgeServices) but no enable field.
# Scanner must detect and emit diagnostic.
# ============================================================
echo "--- Seeded Negative 1: Container attrset with sub-fields, missing enable ---"

sn1_dir="${tmp_dir}/sn1-profiles"
mkdir -p "${sn1_dir}"

cat > "${sn1_dir}/defective.meta.nix" <<'META'
{
  container = {
    advertise = {
      dhcp4 = true;
      radvd = true;
    };
    enableEdgeServices = true;
  };
  assumptionFamily = "edge";
}
META

sn1_violations="${tmp_dir}/sn1-violations.txt"
scan_container_enable "${sn1_dir}" "${sn1_violations}"

sn1_count=$(wc -l < "${sn1_violations}" 2>/dev/null || echo 0)
if [[ "${sn1_count}" -eq 0 ]]; then
  echo "FAIL: Seeded negative 1 — missing-enable profile NOT detected"
  failures=$((failures + 1))
else
  echo "PASS: Seeded negative 1 — scanner detected missing-enable profile (${sn1_count} violation)"
  cat "${sn1_violations}"

  # Verify diagnostic format
  if ! grep -q 'diagnostic.profile-container-enable-missing:defective.meta.nix' "${sn1_violations}"; then
    echo "FAIL: Seeded negative 1 diagnostic missing correct filename"
    failures=$((failures + 1))
  else
    echo "PASS: Seeded negative 1 diagnostic format verified"
  fi
fi
echo ""

# ============================================================
# Seeded Negative 2: Two profiles in deployment — one with
# enable=true (correct), one with container attrset missing
# enable. Scanner must flag ONLY the defective profile.
# ============================================================
echo "--- Seeded Negative 2: Multi-role, one missing enable ---"

sn2_dir="${tmp_dir}/sn2-profiles"
mkdir -p "${sn2_dir}"

# Correct profile: explicit enable = true
cat > "${sn2_dir}/correct.meta.nix" <<'META'
{
  container = {
    enable = true;
    advertise = {
      dhcp4 = false;
      radvd = true;
    };
    enableEdgeServices = false;
  };
  assumptionFamily = "egress";
}
META

# Defective profile: container attrset with sub-fields but no enable
cat > "${sn2_dir}/router.meta.nix" <<'META'
{
  container = {
    advertise = {
      dhcp4 = true;
    };
    enableEdgeServices = true;
  };
  assumptionFamily = "edge";
}
META

sn2_violations="${tmp_dir}/sn2-violations.txt"
scan_container_enable "${sn2_dir}" "${sn2_violations}"

sn2_count=$(wc -l < "${sn2_violations}" 2>/dev/null || echo 0)
if [[ "${sn2_count}" -eq 0 ]]; then
  echo "FAIL: Seeded negative 2 — defective profile NOT detected"
  failures=$((failures + 1))
elif [[ "${sn2_count}" -gt 1 ]]; then
  echo "FAIL: Seeded negative 2 — ${sn2_count} violations, expected exactly 1 (only router.meta.nix)"
  cat "${sn2_violations}"
  failures=$((failures + 1))
else
  echo "PASS: Seeded negative 2 — exactly 1 violation detected"

  # Verify the correct profile is NOT flagged
  if grep -q 'correct.meta.nix' "${sn2_violations}"; then
    echo "FAIL: Seeded negative 2 — correct.meta.nix incorrectly flagged"
    failures=$((failures + 1))
  elif ! grep -q 'router.meta.nix' "${sn2_violations}"; then
    echo "FAIL: Seeded negative 2 — router.meta.nix (defective) not named"
    failures=$((failures + 1))
  else
    echo "PASS: Seeded negative 2 — only defective profile (router.meta.nix) flagged"
    cat "${sn2_violations}"
  fi
fi
echo ""

# ============================================================
# Sanity: Profile with explicit enable = false is valid
# (profile author intentionally disables containers)
# ============================================================
echo "--- Sanity: enable = false is a valid explicit declaration ---"

sanity_dir="${tmp_dir}/sanity-profiles"
mkdir -p "${sanity_dir}"

cat > "${sanity_dir}/disabled.meta.nix" <<'META'
{
  container = {
    enable = false;
    advertise = {
      dhcp4 = false;
      radvd = false;
    };
    enableEdgeServices = false;
  };
  assumptionFamily = "endpoint";
}
META

sanity_violations="${tmp_dir}/sanity-violations.txt"
scan_container_enable "${sanity_dir}" "${sanity_violations}"

sanity_count=$(wc -l < "${sanity_violations}" 2>/dev/null || echo 0)
if [[ "${sanity_count}" -gt 0 ]]; then
  echo "FAIL: Sanity check — enable=false incorrectly flagged as violation"
  failures=$((failures + 1))
else
  echo "PASS: Sanity check — enable=false correctly accepted as explicit declaration"
fi
echo ""

# ============================================================
# Sanity: Profile without container attrset is not flagged
# ============================================================
echo "--- Sanity: No container attrset = valid (no container surface) ---"

sanity2_dir="${tmp_dir}/sanity2-profiles"
mkdir -p "${sanity2_dir}"

cat > "${sanity2_dir}/no-container.meta.nix" <<'META'
{
  assumptionFamily = "selector";
}
META

sanity2_violations="${tmp_dir}/sanity2-violations.txt"
scan_container_enable "${sanity2_dir}" "${sanity2_violations}"

sanity2_count=$(wc -l < "${sanity2_violations}" 2>/dev/null || echo 0)
if [[ "${sanity2_count}" -gt 0 ]]; then
  echo "FAIL: Sanity check — profile without container attrset incorrectly flagged"
  failures=$((failures + 1))
else
  echo "PASS: Sanity check — profile without container attrset correctly skipped"
fi
echo ""

# ============================================================
# Result
# ============================================================
if [[ ${failures} -eq 0 ]]; then
  echo "PASS FS-982-HDS-010-SDS-010-SMS-100 — profile metadata container enable declaration verified"
  exit 0
else
  echo "FAIL FS-982-HDS-010-SDS-010-SMS-100: ${failures} failure(s)"
  exit 1
fi
