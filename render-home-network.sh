#!/usr/bin/env bash
set -euo pipefail

nix run \
    --no-write-lock-file \
    --extra-experimental-features 'nix-command flakes' \
    .#render-dry-config \
    -- \
    --debug \
    "/home/deadbeef/github/nixos/library/100-fabric-routing/inputs/intent.nix" \
    "/home/deadbeef/github/nixos/nixos/virtual-machine/nixos-shell-vm/inventory.nix"
