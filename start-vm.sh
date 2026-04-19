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
detach="${VM_DETACH:-0}"
if [[ "${1:-}" == "--timeout" ]]; then
  vm_timeout="${2:-}"
  if [[ -z "$vm_timeout" ]]; then
    echo "[!] Missing value for --timeout (example: --timeout 10m)" >&2
    exit 1
  fi
  shift 2
fi
if [[ "${1:-}" == "--detach" ]]; then
  detach=1
  shift
fi
if [[ "$#" -gt 0 ]]; then
  echo "usage: ./start-vm.sh [--timeout 10m] [--detach]" >&2
  exit 1
fi

cmd=(nix run --extra-experimental-features 'nix-command flakes' github:Mic92/nixos-shell -- "${FLAKE_DIR}/vm.nix")

# In detached mode, Ctrl+C in your terminal won't kill the VM.
if [[ "$detach" == "1" ]]; then
  out_dir="${FLAKE_DIR}/work/vm"
  mkdir -p "$out_dir"
  log_path="${out_dir}/start-vm.log"
  pid_path="${out_dir}/start-vm.pid"

  echo "[*] Detaching VM process (log: ${log_path})"
  if command -v timeout >/dev/null 2>&1; then
    # `timeout` exits 124 on timeout; detach keeps it out of the current tty/process group.
    nohup setsid -w timeout --foreground "$vm_timeout" "${cmd[@]}" >"$log_path" 2>&1 &
  else
    nohup setsid -w "${cmd[@]}" >"$log_path" 2>&1 &
  fi
  echo $! >"$pid_path"
  disown || true
  echo "[*] VM PID: $(cat "$pid_path")"
  exit 0
fi

if command -v timeout >/dev/null 2>&1; then
  set +e
  timeout --foreground "$vm_timeout" \
    "${cmd[@]}"
  st=$?
  set -e
  if [[ "$st" -eq 124 ]]; then
    echo "[!] VM start timed out after ${vm_timeout}. Re-run with a larger timeout, e.g. --timeout 1h" >&2
  fi
  exit "$st"
else
  echo "[!] 'timeout' command not found; running without a timeout. Set up coreutils if this hangs." >&2
  "${cmd[@]}"
fi
