#!/usr/bin/env bash
set -euo pipefail

intent_path="/home/deadbeef/github/nixos/library/100-fabric-routing/inputs/intent.nix"
inventory_path="/home/deadbeef/github/nixos/nixos/virtual-machine/nixos-shell-vm/inventory.nix"

nix run \
  --no-write-lock-file \
  --extra-experimental-features 'nix-command flakes' \
  .#render-dry-config \
  -- \
  --debug \
  "$intent_path" \
  "$inventory_path"

./test-split-box-render.sh "$intent_path" "$inventory_path" ./90-render.json

cat 90-render.json | jq -c
