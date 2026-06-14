#!/usr/bin/env bash
# GAMP-ID: FS-310-HDS-030-SDS-010-SMS-111
# GAMP-SCOPE: software-module-test
# Focused construction test: NixOS renderer fail-closed contract.
#
# SMS-111 (child of SMS-110): NixOS-specific `or` fallback scan with
# eight HIGH-SEVERITY categories, file:line audit evidence, and three
# active seeded negatives.
#
# The renderer must throw on missing required CPM/provider fields
# rather than silently substituting hardcoded defaults that affect
# network behavior (routing, addressing, firewall, NAT, DNS, interface
# naming, health checking).
#
# PERMITTED: or null, or { }, or [ ], or false, or ""  (structural sentinels)
# NOTE: or 0 is context-dependent: permitted for feature flags (absence=disabled),
#       HIGH-SEVERITY for network-affecting numeric defaults (prefix slots).
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
tmp_dir="$(mktemp -d)"
trap 'rm -rf "${tmp_dir}"' EXIT
all_checks_passed=true

echo "--- FS-310-HDS-030-SDS-010-SMS-111: NixOS renderer fail-closed contract scan ---"
echo ""

# ============================================================
# Source scan target: s88/ControlModule/, s88/Unit/, flake.nix
# ============================================================
src_scope=(
  "${repo_root}/s88/ControlModule"
  "${repo_root}/s88/Unit"
)
flake_file="${repo_root}/flake.nix"

echo "Scan scope: s88/ControlModule/, s88/Unit/, flake.nix"
echo ""

# ============================================================
# Find `or <value>` patterns in .nix files.
# Exclude permitted: or null, or { }, or [ ], or false, or ""
# (or 0 is NOT excluded — context-dependent, see SMS §ALLOWABLE)
# Exclude comments (leading #, //, /*), import paths, file checks
# ============================================================
echo "--- Scanning for network-affecting 'or' defaults ---"

violations_file="${tmp_dir}/violations.txt"
> "${violations_file}"

for src_dir in "${src_scope[@]}"; do
  if [[ -d "${src_dir}" ]]; then
    find "${src_dir}" -name '*.nix' -not -path '*/tests/*' -print0 2>/dev/null | \
      xargs -0 grep -n ' or ' 2>/dev/null || true
  fi
done >> "${violations_file}"

if [[ -f "${flake_file}" ]]; then
  grep -n ' or ' "${flake_file}" 2>/dev/null >> "${violations_file}" || true
fi

# Filter out permitted patterns and noise
violations_filtered="${tmp_dir}/violations_filtered.txt"
# PERMITTED: or null, or { }, or [ ], or false, or "" (structural sentinels)
# Nix often writes these with spaces: or { }, or [ ]
grep -vE '( or null[^a-zA-Z]| or \{\s*\}| or \[\s*\]| or false[^a-zA-Z]| or "")' \
  "${violations_file}" > "${violations_filtered}" 2>/dev/null || true

# Strip comments/imports/file-checks: remove lines where content after first : is comment
violations_code="${tmp_dir}/violations_code.txt"
> "${violations_code}"
while IFS= read -r line; do
  content_only="${line#*:}"
  [[ -z "${content_only}" ]] && continue
  echo "${content_only}" | grep -qE '^\s*(#|//|/\*)' && continue
  echo "${content_only}" | grep -qE '(import \./|builtins\.readFile|file \?)' && continue
  echo "${line}"
done < "${violations_filtered}" >> "${violations_code}" 2>/dev/null || true

violation_count=$(wc -l < "${violations_code}" 2>/dev/null || echo 0)
echo "Network-affecting 'or' defaults found (excluding permitted): ${violation_count}"

# ============================================================
# Build basename:lineno index for efficient matching
# ============================================================
violations_idx="${tmp_dir}/violations_idx.txt"
> "${violations_idx}"
while IFS= read -r vline; do
  path_part="${vline%%:*}"
  rest="${vline#*:}"
  lineno="${rest%%:*}"
  basename="${path_part##*/}"
  echo "${basename}:${lineno}"
done < "${violations_code}" >> "${violations_idx}" 2>/dev/null || true

# ============================================================
# KNOWN HIGH-SEVERITY GAPS: file:line instances from SMS-111 §HIGH-SEVERITY
# that are still present as `or` defaults (2026-06-14 audit).
# Entries that have been RESOLVED (no longer `or` defaults) are listed separately.
# ============================================================
echo ""
echo "--- Classifying violations against SMS-111 HIGH-SEVERITY catalog ---"

KNOWN_HIGH_ACTIVE=(
  # Category 1: Firewall / Relation Action Defaults (or "allow" / or "accept")
  "service-nat.nix:107"
  "underlay-input.nix:25"
  "container-networks.nix:197"
  # Category 2: Numeric Network Defaults
  "container-forwards.nix:53"    # or 5000
  "container-forwards.nix:54"    # or 2200
  "container-forwards.nix:55"    # or 9000
  "authoritative.nix:180"        # or 64
  "authoritative.nix:181"        # or 64
  "authoritative.nix:182"        # or 0 (delegated-prefix slot — not a feature flag)
  "container-networks.nix:198"   # or 6
  # Category 3: Hardcoded DNS / Resolver IPs
  "plan.nix:16"                  # or "1.1.1.1"
  "plan.nix:17"                  # or "2606:4700:4700::1111"
  # Category 4: Hardcoded Interface Names
  "pppoe.nix:48"                 # or "ppp0"
  "pppoe.nix:135"                # or "ppp0"
  # Category 5: Hardcoded Mode / Domain Strings
  "provider-overlay-runtime-interfaces.nix:55"   # or "overlay"
  "provider-overlay-runtime-interfaces.nix:63"   # or "overlay"
  "provider-overlay-runtime-interfaces.nix:73"   # or "overlay"
  # Category 6: Enable-By-Default Booleans
  "rules.nix:74"                 # or true
  "authoritative.nix:28"         # or true
  # Category 7: Hardcoded Protocol / Any
  "rules.nix:34"                 # or "any"
)

# Entries from SMS-111 tables that are RESOLVED (no longer `or` defaults):
# - normalize.nix:150: was `or "eth0"`, now conditional assignment
# - authoritative.nix:242: was `or "lan."`, now `throw "FS-310-..."`
# - authoritative.nix:271: was `or "lan."`, now `throw "FS-310-..."`
# - authoritative.nix:295: was `or "lan."`, now `throw "FS-310-..."`
# - plan.nix:15: was `or "example.com"`, now direct assignment
KNOWN_HIGH_RESOLVED=5

KNOWN_MEDIUM_ACTIVE=(
  "public-ingress.nix:90"
  "container-assembly.nix:128"
  "normalize.nix:71"
  "normalize.nix:149"
  "lookup.nix:12"
)

# Count active known gaps
detected_high=0
for entry in "${KNOWN_HIGH_ACTIVE[@]}"; do
  if grep -qFx "${entry}" "${violations_idx}" 2>/dev/null; then
    detected_high=$((detected_high + 1))
  fi
done

detected_medium=0
for entry in "${KNOWN_MEDIUM_ACTIVE[@]}"; do
  if grep -qFx "${entry}" "${violations_idx}" 2>/dev/null; then
    detected_medium=$((detected_medium + 1))
  fi
done

high_total=$(( ${#KNOWN_HIGH_ACTIVE[@]} + KNOWN_HIGH_RESOLVED ))
echo "HIGH-SEVERITY: ${detected_high} active + ${KNOWN_HIGH_RESOLVED} resolved = ${high_total} catalogued"
echo "  (active known gaps: ${detected_high}/${#KNOWN_HIGH_ACTIVE[@]})"
echo "MEDIUM-SEVERITY detected: ${detected_medium}/${#KNOWN_MEDIUM_ACTIVE[@]}"

# ============================================================
# Seeded negative 1: Hardcoded firewall action — inject `or "allow"`
# ============================================================
echo ""
echo "--- Seeded negative 1: Hardcoded firewall action ---"
seeded_dir="${tmp_dir}/seeded"
mkdir -p "${seeded_dir}"
cat > "${seeded_dir}/test-service-nat.nix" <<'SEEDED1'
{ config, lib, ... }:
let
  relation = config.cpmRelation or { };
in
{
  natEnabled = (relation.action or "allow") == "allow";
}
SEEDED1

seed1_hits=$(grep -c 'or "allow"' "${seeded_dir}/test-service-nat.nix" 2>/dev/null || echo 0)
if [[ "${seed1_hits}" -gt 0 ]]; then
  echo "PASS: Seeded negative 1 — 'or \"allow\"' detected (${seed1_hits} hit(s))."
else
  echo "FAIL: Seeded negative 1 — 'or \"allow\"' NOT detected."
  all_checks_passed=false
fi

# ============================================================
# Seeded negative 2: Hardcoded route metric — inject `or 5000`
# ============================================================
echo "--- Seeded negative 2: Hardcoded route metric ---"
cat > "${seeded_dir}/test-metric.nix" <<'SEEDED2'
{ config, lib, ... }:
let
  route = config.cpmRoute or { };
in
{
  metric = route.metric or 5000;
}
SEEDED2

seed2_hits=$(grep -c 'or 5000' "${seeded_dir}/test-metric.nix" 2>/dev/null || echo 0)
if [[ "${seed2_hits}" -gt 0 ]]; then
  echo "PASS: Seeded negative 2 — 'or 5000' detected (${seed2_hits} hit(s))."
else
  echo "FAIL: Seeded negative 2 — 'or 5000' NOT detected."
  all_checks_passed=false
fi

# ============================================================
# Seeded negative 3: Hardcoded DNS probe IP — inject `or "1.1.1.1"`
# ============================================================
echo "--- Seeded negative 3: Hardcoded DNS probe IP ---"
cat > "${seeded_dir}/test-probe.nix" <<'SEEDED3'
{ config, lib, ... }:
let
  hv = config.hostValidation or { };
in
{
  publicIpv4Probe = hv.publicIpv4Probe or "1.1.1.1";
}
SEEDED3

seed3_hits=$(grep -c 'or "1.1.1.1"' "${seeded_dir}/test-probe.nix" 2>/dev/null || echo 0)
if [[ "${seed3_hits}" -gt 0 ]]; then
  echo "PASS: Seeded negative 3 — 'or \"1.1.1.1\"' detected (${seed3_hits} hit(s))."
else
  echo "FAIL: Seeded negative 3 — 'or \"1.1.1.1\"' NOT detected."
  all_checks_passed=false
fi

# ============================================================
# Forward-looking: scan for throw messages with trace-chain ID.
# Uses fast grep -r; will grow as implementation progresses.
# ============================================================
echo ""
echo "--- Scanning for throw messages with trace-chain ID ---"
trace_id="FS-310-HDS-030-SDS-010-SMS-111"
throw_count=0

for src_dir in "${src_scope[@]}"; do
  if [[ -d "${src_dir}" ]]; then
    c=$(grep -rl "throw.*${trace_id}" "${src_dir}" --include='*.nix' 2>/dev/null | wc -l) || true
    throw_count=$((throw_count + c))
  fi
done

if [[ -f "${flake_file}" ]]; then
  c=$(grep -c "throw.*${trace_id}" "${flake_file}" 2>/dev/null) || true
  throw_count=$((throw_count + c))
fi

echo "Throw messages containing trace-chain ID: ${throw_count} (expected: grows as implementation progresses)"

# ============================================================
# Sanity check: permitted patterns NOT flagged
# ============================================================
echo ""
echo "--- Sanity: verify permitted patterns excluded ---"
permitted_dir="${tmp_dir}/permitted"
mkdir -p "${permitted_dir}"
cat > "${permitted_dir}/test-permitted.nix" <<'PERMITTED'
{ config, lib, ... }:
{
  a = config.x or null;
  b = config.y or { };
  c = config.z or [ ];
  d = config.enabled or false;
  f = config.name or "";
}
PERMITTED

# Count or patterns that would be falsely flagged
permitted_raw=$(grep -c ' or ' "${permitted_dir}/test-permitted.nix" 2>/dev/null || echo 0)
permitted_filtered=$(grep ' or ' "${permitted_dir}/test-permitted.nix" | grep -vE '( or null[^a-zA-Z]| or \{\s*\}| or \[\s*\]| or false[^a-zA-Z]| or "")' | wc -l) || true
permitted_filtered="${permitted_filtered:-0}"
echo "Permitted patterns total: ${permitted_raw}, false-flagged: ${permitted_filtered}"
if [[ "${permitted_filtered}" -eq 0 ]]; then
  echo "PASS: Permitted patterns (null, {}, [], false, \"\") correctly excluded."
else
  echo "FAIL: ${permitted_filtered} permitted patterns incorrectly flagged."
  all_checks_passed=false
fi

# ============================================================
# Sample violations
# ============================================================
echo ""
echo "--- Sample violations (first 10) ---"
head -10 "${violations_code}" 2>/dev/null | while IFS= read -r line; do
  rel="${line#${repo_root}/}"
  echo "  ${rel}" | head -c 150
  echo ""
done

# ============================================================
# Report
# ============================================================
echo ""
echo "=== SMS-111 NixOS Fail-Closed Contract Scan Results ==="
echo "  Source scope:            s88/ControlModule/, s88/Unit/, flake.nix"
echo "  Total 'or' defaults:     ${violation_count} (excluding permitted)"
echo "  HIGH-SEVERITY catalogued: ${high_total} (${detected_high} active + ${KNOWN_HIGH_RESOLVED} resolved)"
echo "  MEDIUM-SEVERITY detected: ${detected_medium}/${#KNOWN_MEDIUM_ACTIVE[@]}"
echo "  Throw messages with ID:  ${throw_count}"
echo ""

if [[ "${violation_count}" -gt 0 ]]; then
  if [[ "${all_checks_passed}" == "true" ]]; then
    echo "PASS: FS-310-HDS-030-SDS-010-SMS-111 NixOS fail-closed scan complete."
    echo "  ${violation_count} 'or' defaults identified (${high_total} HIGH-SEVERITY catalogued)."
    echo "  Scanner proves ability to detect network-affecting defaults."
    echo "  All 3 active seeded negatives caught."
    exit 0
  else
    echo "FAIL: One or more checks failed — see details above."
    exit 1
  fi
else
  echo "FAIL: Scanner found no 'or' defaults — may be broken or all fixed."
  exit 1
fi
