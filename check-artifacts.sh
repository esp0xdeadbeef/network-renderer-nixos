#!/usr/bin/env bash
set -euo pipefail

out_dir="${1:-./work/etc}"
tmp_dir="$(mktemp -d "${TMPDIR:-/tmp}/network-renderer-nixos-artifacts.XXXXXX")"
trap 'rm -rf "$tmp_dir"' EXIT

expr='
let
  input = import ./vm-input.nix;
  system = if builtins ? currentSystem then builtins.currentSystem else "x86_64-linux";
  renderer = (builtins.getFlake (toString ./. )).libBySystem.${system};

  etcEntries =
    (renderer.artifacts.controlPlaneSplitFromPaths {
      intentPath = input.intentPath;
      inventoryPath = input.inventoryPath;
      fileName = "control-plane-model.json";
      directory = "network-artifacts";
    }).environment.etc;

  artifactNames = builtins.filter
    (name: builtins.match "network-artifacts/.*" name != null)
    (builtins.attrNames etcEntries);
in
builtins.listToAttrs (map (name: {
  inherit name;
  value = toString etcEntries.${name}.source;
}) artifactNames)
'

mkdir -p "$tmp_dir"

nix eval --impure --json --expr "$expr" \
| jq -r 'to_entries | sort_by(.key)[] | [.key, .value] | @tsv' \
| while IFS=$'\t' read -r etc_path source_path; do
    rel="${etc_path#/}"
    target="${tmp_dir}/${rel}"
    mkdir -p "$(dirname "$target")"
    ln -sf "$source_path" "$target"
  done

rm -rf "$out_dir"
mkdir -p "$(dirname "$out_dir")"
mv "$tmp_dir" "$out_dir"
trap - EXIT

find "$out_dir" \( -type l -o -type f \) | sort
