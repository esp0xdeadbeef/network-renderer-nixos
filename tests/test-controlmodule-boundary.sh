#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

violations="$(
  rg -n \
    '../..*/(Unit|EquipmentModule|Site)|import .*\\b(Unit|EquipmentModule|Site)\\b' \
    "${repo_root}/s88/ControlModule" \
    -g '*.nix' || true
)"

if [[ -n "${violations}" ]]; then
  echo "ControlModule files must not import Unit, EquipmentModule, or Site code:" >&2
  printf '%s\n' "${violations}" >&2
  exit 1
fi

for removed_entrypoint in \
  "${repo_root}/s88/ControlModule/api/default.nix" \
  "${repo_root}/s88/ControlModule/api/box-build-inputs.nix" \
  "${repo_root}/s88/ControlModule/api/host-build.nix" \
  "${repo_root}/s88/ControlModule/api/module-host-build.nix" \
  "${repo_root}/s88/ControlModule/render/host-plan.nix" \
  "${repo_root}/s88/ControlModule/render/host-network.nix" \
  "${repo_root}/s88/ControlModule/render/dry-config-output.nix" \
  "${repo_root}/s88/ControlModule/pipeline/fabric-input-loader.nix" \
  "${repo_root}/s88/ControlModule/module/host-network.nix" \
  "${repo_root}/s88/ControlModule/module/container-runtime.nix"
do
  if [[ -e "${removed_entrypoint}" ]]; then
    echo "Context-selecting entrypoint belongs above ControlModule: ${removed_entrypoint}" >&2
    exit 1
  fi
done
