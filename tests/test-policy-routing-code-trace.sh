#!/usr/bin/env bash
# GAMP-ID: USR-MODEL-001-FS-001-HDS-002-SDS-001-001-SMS-001-006
# GAMP-ID: USR-MODEL-001-FS-001-HDS-002-SDS-001-001-SMS-001-007
# GAMP-ID: USR-MODEL-001-FS-001-HDS-002-SDS-001-006-SMS-001-004
# GAMP-ID: USR-MODEL-001-FS-001-HDS-002-SDS-001-006-SMS-001-005
# GAMP-ID: USR-MODEL-001-FS-001-HDS-002-SDS-001-001-SMS-001-CMC-001-006
# GAMP-ID: USR-MODEL-001-FS-001-HDS-002-SDS-001-001-SMS-001-CMC-001-007
# GAMP-ID: USR-MODEL-001-FS-001-HDS-002-SDS-001-006-SMS-001-CMC-001-004
# GAMP-ID: USR-MODEL-001-FS-001-HDS-002-SDS-001-006-SMS-001-CMC-001-005
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
trace_file="${repo_root}/s88/ControlModule/render/container-networks/policy-routing/TRACE.md"
policy_dir="${repo_root}/s88/ControlModule/render/container-networks/policy-routing"
top_level="s88/ControlModule/render/container-networks/policy-routing.nix"

fail() {
  echo "FAIL policy-routing-code-trace: $*" >&2
  exit 1
}

[[ -f "${trace_file}" ]] || fail "missing ${trace_file}"

grep -Fq "USR-MODEL-001-FS-001-HDS-002-SDS-001-001-SMS-001-006" "${trace_file}" || fail "TRACE.md missing NixOS route SMS parent"
grep -Fq "USR-MODEL-001-FS-001-HDS-002-SDS-001-001-SMS-001-007" "${trace_file}" || fail "TRACE.md missing NixOS policy-rule SMS parent"
grep -Fq "USR-MODEL-001-FS-001-HDS-002-SDS-001-001-SMS-001-CMC-001-006" "${trace_file}" || fail "TRACE.md missing NixOS route CMC parent"
grep -Fq "USR-MODEL-001-FS-001-HDS-002-SDS-001-001-SMS-001-CMC-001-007" "${trace_file}" || fail "TRACE.md missing NixOS policy-rule CMC parent"
grep -Fq "USR-MODEL-001-FS-001-HDS-002-SDS-001-006-SMS-001-004" "${trace_file}" || fail "TRACE.md missing NixOS route request-surface SMS parent"
grep -Fq "USR-MODEL-001-FS-001-HDS-002-SDS-001-006-SMS-001-005" "${trace_file}" || fail "TRACE.md missing NixOS policy-rule request-surface SMS parent"
grep -Fq "Dead-code rule" "${trace_file}" || fail "TRACE.md missing dead-code rule"

check_surface() {
  local rel="$1"
  local row

  [[ -f "${repo_root}/${rel}" ]] || fail "traced CODE surface does not exist: ${rel}"
  row="$(grep -F "| \`${rel}\` |" "${trace_file}" || true)"
  [[ -n "${row}" ]] || fail "CODE surface is not listed in TRACE.md: ${rel}"
  [[ "${row}" == *"CMC-FUNC-POLICY-ROUTING-"* ]] || fail "TRACE.md row lacks CMC function for ${rel}"
  [[ "${row}" == *"ControlModule"* ]] || fail "TRACE.md row lacks S88 ControlModule layer for ${rel}"
  [[ "${row}" != *"|  |"* ]] || fail "TRACE.md row has an empty required field for ${rel}"
}

check_surface "${top_level}"

while IFS= read -r abs; do
  rel="${abs#${repo_root}/}"
  check_surface "${rel}"
done < <(find "${policy_dir}" -type f -name '*.nix' | sort)

while IFS= read -r rel; do
  [[ -f "${repo_root}/${rel}" ]] || fail "TRACE.md references missing CODE surface: ${rel}"
done < <(
  grep -Eo '`s88/ControlModule/render/container-networks/policy-routing[^`]+\.nix`' "${trace_file}" \
    | tr -d '`' \
    | sort -u
)

echo "PASS policy-routing-code-trace"
