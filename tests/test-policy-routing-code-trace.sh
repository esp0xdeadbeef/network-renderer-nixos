#!/usr/bin/env bash
# GAMP-ID: SMT-NIXOS-POLICY-ROUTING-CODE-TRACE-001
# SDS: SDS-SW-021-005, UP-006-OP-001-PH-002
# SMS: SMS-MOD-007-003
# CMC: CMC-MOD-006-004, CMC-FUNC-POLICY-ROUTING-001..010
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

grep -Fq "SDS-SW-021-005" "${trace_file}" || fail "TRACE.md missing SDS route/rule parent"
grep -Fq "UP-006-OP-001-PH-002" "${trace_file}" || fail "TRACE.md missing software-recipe phase parent"
grep -Fq "SMS-MOD-007-003" "${trace_file}" || fail "TRACE.md missing SMS route/rule parent"
grep -Fq "CMC-MOD-006-004" "${trace_file}" || fail "TRACE.md missing NixOS route/rule CMC parent"
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
