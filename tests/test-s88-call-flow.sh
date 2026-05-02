#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

cm_direct_imports="$(
  cd "$repo_root"
  rg -n 'import[[:space:]]+.*ControlModule' flake.nix s88 -g '*.nix' \
    | awk -F: '
      $1 !~ /^s88\/ControlModule\// &&
      $1 !~ /^s88\/EquipmentModule\// &&
      $1 !~ /^s88\/Unit\// &&
      $1 !~ /^s88\/Site\// {
        print
      }' || true
)"

if [[ -n "$cm_direct_imports" ]]; then
  echo "S88 call flow violation: ControlModules must be reached from Unit, EquipmentModule, or Site, not top-level/Area/Enterprise/ProcessCell code:" >&2
  printf '%s\n' "$cm_direct_imports" >&2
  exit 1
fi

upward_cm_imports="$(
  rg -n '../..*/(Unit|EquipmentModule|Site)|import .*\\b(Unit|EquipmentModule|Site)\\b' \
    "$repo_root/s88/ControlModule" \
    -g '*.nix' || true
)"

if [[ -n "$upward_cm_imports" ]]; then
  echo "S88 call flow violation: ControlModules must not import upward layers:" >&2
  printf '%s\n' "$upward_cm_imports" >&2
  exit 1
fi
