#!/usr/bin/env bash
set -euo pipefail

touch ./nixos.qcow2
#rm ./nixos.qcow2
echo "ssh -o 'StrictHostKeyChecking no' -p2222 root@localhost # to connect to the vm."

FLAKE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "[*] Starting VM via nixos-shell (preserving custom options)..."

# Guard against a stuck build/run (common when QEMU or Nix evaluations hang).
# Override with `VM_TIMEOUT=...` (e.g. `10m`, `1h`) or `--timeout ...`.
vm_timeout="${VM_TIMEOUT:-30m}"
if [[ "${1:-}" == "--timeout" ]]; then
  vm_timeout="${2:-}"
  if [[ -z "$vm_timeout" ]]; then
    echo "[!] Missing value for --timeout (example: --timeout 10m)" >&2
    exit 1
  fi
  shift 2
fi
if [[ "$#" -gt 0 ]]; then
  echo "usage: ./start-vm.sh [--timeout 10m]" >&2
  exit 1
fi

if command -v timeout >/dev/null 2>&1; then
  set +e
  timeout --foreground "$vm_timeout" \
    nix run --extra-experimental-features 'nix-command flakes' github:Mic92/nixos-shell -- "${FLAKE_DIR}/vm.nix"
  st=$?
  set -e
  if [[ "$st" -eq 124 ]]; then
    echo "[!] VM start timed out after ${vm_timeout}. Re-run with a larger timeout, e.g. --timeout 1h" >&2
  fi
  exit "$st"
else
  echo "[!] 'timeout' command not found; running without a timeout. Set up coreutils if this hangs." >&2
  nix run --extra-experimental-features 'nix-command flakes' github:Mic92/nixos-shell -- "${FLAKE_DIR}/vm.nix"
fi
