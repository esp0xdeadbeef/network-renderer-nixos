#!/usr/bin/env bash
set -euo pipefail

intent_path="/home/deadbeef/github/nixos/library/100-fabric-routing/inputs/intent.nix"
inventory_path="/home/deadbeef/github/nixos/nixos/virtual-machine/nixos-shell-vm/inventory.nix"
inventory_path="/home/deadbeef/github/nixos/nixos/virtual-machine/nixos-shell-vm/s-router-test/inventory.nix"

nix run \
  --no-write-lock-file \
  --extra-experimental-features 'nix-command flakes' \
  .#render-dry-config \
  -- \
  --debug \
  "$intent_path" \
  "$inventory_path"

if [ ! -f ./90-render.json ]; then
  if [ -f ./90-dry-config.json ]; then
    jq '.render' ./90-dry-config.json > ./90-render.json
  else
    echo "[!] Missing render artifact: ./90-render.json" >&2
    exit 1
  fi
fi

./test-split-box-render.sh "$intent_path" "$inventory_path" ./90-render.json

jq -c . ./90-render.json
