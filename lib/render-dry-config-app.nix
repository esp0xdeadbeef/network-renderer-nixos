{ pkgs, self ? null }:

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
    repo_root='${builtins.toString ../.}'
    render_file="$repo_root/lib/render-dry-config-output.nix"

    debug_value=false
    case "''${RENDER_DRY_CONFIG_DEBUG:-0}" in
      1|true|TRUE|yes|YES)
        debug_value=true
        ;;
    esac

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
          debug = $debug_value;
        }
      " \
      > 90-dry-config.json

    jq '.metadata.sourcePaths' 90-dry-config.json > 10-paths.json
    jq '.render.hosts' 90-dry-config.json > 30-host-networks.json

    if jq -e '.debug != null' 90-dry-config.json >/dev/null; then
      jq '.debug.inputs.intent' 90-dry-config.json > 00-intent.json
      jq '.debug.inputs.inventory' 90-dry-config.json > 01-inventory.json
      jq '.debug.hardware' 90-dry-config.json > 21-hardware.json
      jq '.debug.realization' 90-dry-config.json > 22-realization.json
      jq '.debug.portAttachTargets' 90-dry-config.json > 23-port-attach-targets.json
      jq '.debug.enterprises' 90-dry-config.json > 24-enterprises.json
    fi

    cp 90-dry-config.json 90-render.json
    jq . 90-dry-config.json
  '';
}
