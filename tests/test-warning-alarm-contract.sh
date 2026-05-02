#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${repo_root}/tests/lib/test-common.sh"

tmp_dir="$(mktemp -d "${TMPDIR:-/tmp}/network-renderer-nixos-warning-contract.XXXXXX")"
trap 'rm -rf "${tmp_dir}"' EXIT

labs_root="$(flake_input_path network-labs)"
clean_example="${labs_root}/examples/single-wan"
clean_cpm="${tmp_dir}/clean-cpm.json"
clean_render="${tmp_dir}/clean-render.json"
clean_stderr="${tmp_dir}/clean-render.stderr"

build_cpm_json "${clean_example}/intent.nix" "${clean_example}/inventory-nixos.nix" "$clean_cpm"

REPO_ROOT="${repo_root}" \
CPM_PATH="$clean_cpm" \
INVENTORY_PATH="${clean_example}/inventory-nixos.nix" \
  nix eval \
    --extra-experimental-features 'nix-command flakes' \
    --impure --json \
    --expr '
      let
        flake = builtins.getFlake ("path:" + builtins.getEnv "REPO_ROOT");
      in
      flake.lib.renderer.renderDryConfig {
        cpmPath = builtins.getEnv "CPM_PATH";
        inventoryPath = builtins.getEnv "INVENTORY_PATH";
        exampleDir = builtins.dirOf (builtins.getEnv "CPM_PATH");
        debug = true;
      }
    ' \
    > "$clean_render" \
    2> "$clean_stderr"

assert_clean_render_contract "warning-alarm-clean-fixture" "$clean_render" "$clean_stderr"

warning_render="${tmp_dir}/warning-render.json"

REPO_ROOT="${repo_root}" \
CPM_PATH="$clean_cpm" \
INVENTORY_PATH="${clean_example}/inventory-nixos.nix" \
  nix eval \
    --extra-experimental-features 'nix-command flakes' \
    --impure --json \
    --expr '
      let
        flake = builtins.getFlake ("path:" + builtins.getEnv "REPO_ROOT");
        cpm = builtins.fromJSON (builtins.readFile (builtins.getEnv "CPM_PATH"));
        cpmWithWarning =
          cpm
          // {
            alarms = [
              {
                alarmId = "s88-warning-contract-sentinel";
                message = "S88_WARNING_CONTRACT_SENTINEL";
                summary = "S88 warning contract sentinel";
                severity = "warning";
                file = "tests/test-warning-alarm-contract.sh";
              }
            ];
            warnings = [ "S88_DIRECT_WARNING_CONTRACT_SENTINEL" ];
          };
      in
      flake.lib.renderer.renderDryConfig {
        cpm = cpmWithWarning;
        inventoryPath = builtins.getEnv "INVENTORY_PATH";
        exampleDir = builtins.dirOf (builtins.getEnv "CPM_PATH");
        debug = true;
      }
    ' \
    > "$warning_render"

_jq -e '
  [
    ..
    | objects
    | select(
        ((.alarms? // []) | any(.alarmId == "s88-warning-contract-sentinel"))
        or ((.warnings? // []) | any(. == "S88_WARNING_CONTRACT_SENTINEL" or . == "S88_DIRECT_WARNING_CONTRACT_SENTINEL"))
        or ((.warningMessages? // []) | any(. == "S88_WARNING_CONTRACT_SENTINEL" or . == "S88_DIRECT_WARNING_CONTRACT_SENTINEL"))
      )
  ]
  | length > 0
' "$warning_render" >/dev/null \
  || fail "synthetic renderer warning/alarm did not propagate into render output"

warning_module_stderr="${tmp_dir}/warning-module.stderr"
if ! nix eval \
  --extra-experimental-features 'nix-command flakes' \
  --impure --raw \
  --expr '
    let
      flake = builtins.getFlake ("path:" + toString '"${repo_root}"');
      system = builtins.currentSystem;
      hostNetworkModule = import '"${repo_root}"'/s88/Unit/module/host-network.nix;
      nixos = flake.inputs.nixpkgs.lib.nixosSystem {
        inherit system;
        modules = [
          ({ ... }: {
            networking.hostName = "s88-warning-contract";
            system.stateVersion = "25.11";
            fileSystems."/" = {
              device = "nodev";
              fsType = "tmpfs";
            };
            boot.loader.grub.enable = false;
          })
          (args: hostNetworkModule (args // {
            controlPlaneOut = { };
            globalInventory = { };
            renderedHostNetwork = {
              warnings = [ "S88_NIXOS_REBUILD_WARNING_SENTINEL" ];
              netdevs = { };
              networks = { };
            };
          }))
        ];
      };
    in
    nixos.config.system.build.toplevel.drvPath
  ' \
  >/dev/null \
  2> "$warning_module_stderr"
then
  cat "$warning_module_stderr" >&2
  fail "synthetic NixOS warning module failed to evaluate"
fi

if ! rg -qF "evaluation warning: S88_NIXOS_REBUILD_WARNING_SENTINEL" "$warning_module_stderr"; then
  cat "$warning_module_stderr" >&2
  fail "renderer warnings did not surface as NixOS evaluation warnings"
fi

missing_stderr="${tmp_dir}/missing-input.stderr"
if REPO_ROOT="${repo_root}" nix eval \
  --extra-experimental-features 'nix-command flakes' \
  --impure --json \
  --expr '
    let
      flake = builtins.getFlake ("path:" + builtins.getEnv "REPO_ROOT");
    in
    flake.lib.renderer.renderDryConfig {
      cpmPath = "/definitely/missing/s88-cpm.json";
      inventoryPath = "/definitely/missing/inventory-nixos.nix";
      debug = true;
    }
  ' \
  >/dev/null \
  2> "$missing_stderr"
then
  fail "renderer accepted missing inputs instead of failing hard"
fi

if ! rg -q "missing required input path|error:" "$missing_stderr"; then
  cat "$missing_stderr" >&2
  fail "renderer failure did not include a visible error"
fi

echo "PASS warning-alarm-contract"
