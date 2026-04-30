{ pkgs }:

pkgs.writeShellScriptBin "s88-network-validation-status" ''
  set -euo pipefail

  target="/run/s88-network-validation/stable.json"
  if [ ! -f "$target" ]; then
    target="/run/s88-network-validation/status.json"
  fi

  if [ ! -f "$target" ]; then
    echo "no validation snapshot yet" >&2
    exit 1
  fi

  exec ${pkgs.jq}/bin/jq . "$target"
''
