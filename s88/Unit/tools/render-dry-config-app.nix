{ pkgs, ... }:

pkgs.writeShellApplication {
  name = "render-dry-config";

  runtimeInputs = with pkgs; [
    coreutils
    jq
  ];

  text = ''
    set -euo pipefail

    usage() {
      echo "usage: render-dry-config [--debug] <control-plane.{nix,json}>" >&2
    }

    debug_value=false
    positional=()

    while [ "$#" -gt 0 ]; do
      case "$1" in
        --debug)
          debug_value=true
          shift
          ;;
        --)
          shift
          while [ "$#" -gt 0 ]; do
            positional+=("$1")
            shift
          done
          ;;
        -*)
          usage
          exit 1
          ;;
        *)
          positional+=("$1")
          shift
          ;;
      esac
    done

    set -- "''${positional[@]}"

    if [ "$#" -ne 1 ]; then
      usage
      exit 1
    fi

    repo_root='${builtins.toString ../../..}'

    rm -f ./[0-9][0-9]-*.json

    run_nix_eval_json() {
      local expr="$1"
      local output_path="$2"
      nix eval --impure --json --expr "$expr" > "$output_path"
    }

    cpm_path="$(realpath "$1")"
    example_dir="$(dirname "$cpm_path")"

    run_nix_eval_json "
      let
        flake = builtins.getFlake (toString (builtins.toPath \"$repo_root\"));
      in
      flake.lib.renderer.renderDryConfig {
        cpmPath = \"$cpm_path\";
        exampleDir = \"$example_dir\";
        debug = $debug_value;
      }
    " 90-dry-config.json

    jq '.metadata' 90-dry-config.json > 10-metadata.json
    jq '.metadata.sourcePaths' 90-dry-config.json > 11-source-paths.json
    jq '.render.hosts' 90-dry-config.json > 30-hosts.json
    jq '.render.nodes' 90-dry-config.json > 31-nodes.json
    jq '.render.containers' 90-dry-config.json > 32-containers.json
    jq '.render' 90-dry-config.json > 90-render.json

    if jq -e '.debug != null' 90-dry-config.json >/dev/null; then
      jq '.debug.controlPlane' 90-dry-config.json > 04-control-plane.rendered.json
      jq '.debug.inventory' 90-dry-config.json > 05-inventory.rendered.json
      jq '.debug.normalizedRuntimeTargets' 90-dry-config.json > 25-runtime-targets.json
      jq '.debug.hostRenderings' 90-dry-config.json > 35-host-renderings.json
    fi
  '';
}
