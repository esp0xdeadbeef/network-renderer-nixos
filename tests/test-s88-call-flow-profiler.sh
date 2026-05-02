#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
profile_dir="$(mktemp -d)"
profile_file="${profile_dir}/nix.profile"
system="$(nix eval --impure --raw --expr builtins.currentSystem)"

nix eval \
  --option eval-profiler flamegraph \
  --option eval-profile-file "${profile_file}" \
  "${repo_root}#packages.${system}.s88-call-flow-eval-target.drvPath" \
  >/dev/null

if [[ ! -s "${profile_file}" ]]; then
  echo "Nix eval profiler did not produce a usable flamegraph profile" >&2
  exit 1
fi

s88_stacks="$(rg '/s88/(Site|Unit|EquipmentModule|ControlModule)/' "${profile_file}" || true)"

if [[ -z "${s88_stacks}" ]]; then
  echo "Profiler output did not include S88 call frames; call-flow test is not exercising the renderer" >&2
  exit 1
fi

cm_stacks="$(printf '%s\n' "${s88_stacks}" | rg '/s88/ControlModule/' || true)"

if [[ -z "${cm_stacks}" ]]; then
  echo "Profiler output did not include ControlModule frames; call-flow test is not exercising CM rendering" >&2
  exit 1
fi

violations="$(
  printf '%s\n' "${cm_stacks}" \
    | awk '
      /\/s88\/ControlModule\// {
        cm = index($0, "/s88/ControlModule/")
        site = index($0, "/s88/Site/")
        unit = index($0, "/s88/Unit/")
        em = index($0, "/s88/EquipmentModule/")
        ok = (site > 0 && site < cm) || (unit > 0 && unit < cm) || (em > 0 && em < cm)
        if (!ok) print
      }'
)"

if [[ -n "${violations}" ]]; then
  echo "S88 profiler call-flow violation: ControlModule frame appeared without an earlier Site, Unit, or EquipmentModule frame:" >&2
  printf '%s\n' "${violations}" >&2
  exit 1
fi
