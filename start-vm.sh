#!/usr/bin/env bash
set -euo pipefail

touch ./nixos.qcow2
rm ./nixos.qcow2
echo "ssh -o 'StrictHostKeyChecking no' -p2222 root@localhost # to connect to the vm."

FLAKE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "[*] Starting VM via nixos-shell (preserving custom options)..."
nix run --extra-experimental-features 'nix-command flakes' github:Mic92/nixos-shell -- "${FLAKE_DIR}/vm.nix"
