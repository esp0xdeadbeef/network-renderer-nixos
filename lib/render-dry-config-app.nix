{ pkgs, self }:

pkgs.writeShellApplication {
  name = "render-dry-config";

  runtimeInputs = with pkgs; [
    bash
    coreutils
    jq
    nix
  ];

  text = ''
    set -euo pipefail

    if [ "$#" -ne 2 ]; then
      echo "usage: render-dry-config <intent.nix> <inventory.nix>" >&2
      exit 1
    fi

    intent_path="$(realpath "$1")"
    inventory_path="$(realpath "$2")"
    example_dir="$(dirname "$intent_path")"
    repo_root='${self}'
    render_file="$repo_root/lib/render-dry-config-output.nix"

    rm -f \
      ./00-*.json \
      ./01-*.json \
      ./10-*.json \
      ./20-*.json \
      ./21-*.json \
      ./22-*.json \
      ./23-*.json \
      ./24-*.json \
      ./30-*.json \
      ./90-*.json

    nix eval \
      --impure \
      --json \
      --expr "
        import (builtins.toPath \"$render_file\") {
          repoRoot = \"$repo_root\";
          intentPath = \"$intent_path\";
          inventoryPath = \"$inventory_path\";
          exampleDir = \"$example_dir\";
        }
      " \
      > 90-dry-config.json

    jq '.inputs.intent' 90-dry-config.json > 00-intent.json
    jq '.inputs.inventory' 90-dry-config.json > 01-inventory.json
    jq '.vars.paths' 90-dry-config.json > 10-paths.json
    jq '.vars.hardware' 90-dry-config.json > 21-hardware.json
    jq '.vars.realization' 90-dry-config.json > 22-realization.json
    jq '.vars.portAttachTargets' 90-dry-config.json > 23-port-attach-targets.json
    jq '.vars.enterprises' 90-dry-config.json > 24-enterprises.json
    jq '.vars.hostNetworks' 90-dry-config.json > 30-host-networks.json

    cp 90-dry-config.json 90-render.json
    jq . 90-dry-config.json
  '';
}
