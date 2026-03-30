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
      echo "usage: render-dry-config [--debug] <control-plane.{nix,json}> | render-dry-config [--debug] <intent.nix> <inventory.nix>" >&2
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

    if [ "$#" -ne 1 ] && [ "$#" -ne 2 ]; then
      usage
      exit 1
    fi

    repo_root='${builtins.toString ../../..}'
    render_file="$repo_root/s88/ControlModule/render/dry-config-output.nix"

    rm -f \
      ./00-*.json \
      ./01-*.json \
      ./02-*.json \
      ./03-*.json \
      ./04-*.json \
      ./10-*.json \
      ./25-*.json \
      ./30-*.json \
      ./90-*.json

    run_nix_eval_json() {
      local expr="$1"
      local output_path="$2"

      nix eval \
        --impure \
        --json \
        --expr "$expr" \
        > "$output_path"
    }

    render_from_cpm_path() {
      local cpm_path="$1"
      local example_dir="$2"

      run_nix_eval_json "
        import (builtins.toPath \"$render_file\") {
          repoRoot = \"$repo_root\";
          cpmPath = \"$cpm_path\";
          exampleDir = \"$example_dir\";
          debug = $debug_value;
        }
      " 90-dry-config.json
    }

    build_compiler_artifact() {
      local intent_path="$1"

      run_nix_eval_json "
        let
          flake = builtins.getFlake (toString (builtins.toPath \"$repo_root\"));
        in
        flake.lib.renderer.buildCompilerFromPaths {
          intentPath = \"$intent_path\";
        }
      " 02-compiler.json
    }

    build_forwarding_artifact() {
      local intent_path="$1"

      run_nix_eval_json "
        let
          flake = builtins.getFlake (toString (builtins.toPath \"$repo_root\"));
        in
        flake.lib.renderer.buildForwardingFromPaths {
          intentPath = \"$intent_path\";
        }
      " 03-forwarding.json
    }

    build_control_plane_artifact() {
      local intent_path="$1"
      local inventory_path="$2"

      run_nix_eval_json "
        let
          flake = builtins.getFlake (toString (builtins.toPath \"$repo_root\"));
        in
        flake.lib.renderer.buildControlPlaneFromPaths {
          intentPath = \"$intent_path\";
          inventoryPath = \"$inventory_path\";
        }
      " 04-control-plane.json
    }

    render_from_built_cpm() {
      local example_dir="$1"
      local inventory_path="$2"

      run_nix_eval_json "
        import (builtins.toPath \"$render_file\") {
          repoRoot = \"$repo_root\";
          cpmPath = \"$(realpath ./04-control-plane.json)\";
          inventoryPath = \"$inventory_path\";
          exampleDir = \"$example_dir\";
          debug = $debug_value;
        }
      " 90-dry-config.json
    }

    if [ "$#" -eq 1 ]; then
      cpm_path="$(realpath "$1")"
      example_dir="$(dirname "$cpm_path")"

      render_from_cpm_path "$cpm_path" "$example_dir"
    else
      first_path="$(realpath "$1")"
      second_path="$(realpath "$2")"
      first_base="$(basename "$first_path")"
      second_base="$(basename "$second_path")"

      intent_path="$first_path"
      inventory_path="$second_path"

      if [ "$first_base" = "inventory.nix" ] && [ "$second_base" = "intent.nix" ]; then
        inventory_path="$first_path"
        intent_path="$second_path"
      elif [ "$first_base" = "intent.nix" ] && [ "$second_base" = "inventory.nix" ]; then
        intent_path="$first_path"
        inventory_path="$second_path"
      fi

      example_dir="$(dirname "$intent_path")"

      if [ "$debug_value" = true ]; then
        build_compiler_artifact "$intent_path"
        build_forwarding_artifact "$intent_path"
      fi

      if ! build_control_plane_artifact "$intent_path" "$inventory_path"; then
        rm -f ./90-dry-config.json ./90-render.json

        if [ -f ./03-forwarding.json ] && jq -e '
          .meta.networkForwardingModel.contracts.output.transit.ordering.shape == "stable-link-ids"
          and
          .meta.networkForwardingModel.contracts.normalization.site.transit.nodePairOrdering.shape == "node-pairs"
        ' ./03-forwarding.json >/dev/null 2>&1; then
          echo "render-dry-config: wrapper-mode CPM generation failed before renderer input existed" >&2
          echo "render-dry-config: upstream-blocked by network-forwarding-model transit.ordering contract mismatch" >&2
          echo "render-dry-config: emitted output shape is stable-link-ids, while validation still expects node-pairs" >&2
        else
          echo "render-dry-config: wrapper-mode CPM generation failed before renderer input existed" >&2
        fi

        exit 1
      fi

      render_from_built_cpm "$example_dir" "$inventory_path"
    fi

    jq '.metadata.sourcePaths' 90-dry-config.json > 10-paths.json
    jq '.render.hosts' 90-dry-config.json > 30-host-networks.json

    if jq -e '.debug != null' 90-dry-config.json >/dev/null; then
      jq '.debug.controlPlane' 90-dry-config.json > 04-control-plane.rendered.json
      jq '.debug.normalizedRuntimeTargets' 90-dry-config.json > 25-runtime-targets.json
    fi

    jq '.render' 90-dry-config.json > 90-render.json
  '';
}
