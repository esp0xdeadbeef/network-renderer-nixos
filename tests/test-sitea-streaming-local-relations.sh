#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${repo_root}/tests/lib/test-common.sh"

example_root="$(flake_input_path network-labs)/examples/s-router-overlay-dns-lane-policy"
intent_path="${example_root}/intent.nix"
inventory_path="${example_root}/inventory-nixos.nix"

[[ -f "${intent_path}" ]] || { echo "missing intent: ${intent_path}" >&2; exit 1; }
[[ -f "${inventory_path}" ]] || { echo "missing inventory: ${inventory_path}" >&2; exit 1; }

read -r -d '' expr <<'EOF' || true
let
  repoRoot = "path:" + builtins.getEnv "REPO_ROOT";
  intentPath = builtins.getEnv "INTENT_PATH";
  inventoryPath = builtins.getEnv "INVENTORY_PATH";
  flake = builtins.getFlake repoRoot;
  system = builtins.currentSystem;
  hostBuild = import (builtins.getEnv "REPO_ROOT" + "/tests/nix/build-host-from-paths.nix") {
    selector = "s-router-test";
    inherit system intentPath inventoryPath;
  };
  rendered = hostBuild.renderedHost;
  policyCfg =
    (flake.inputs.nixpkgs.lib.nixosSystem {
      inherit system;
      modules = [ rendered.containers."s-router-policy-only".config ];
    }).config;
  rules = policyCfg.networking.nftables.ruleset;
in
  builtins.substring 0 0 "" == ""
  && flake.inputs.nixpkgs.lib.hasInfix "iifname \"down-client\" oifname \"downstr-stream\" accept comment \"allow-sitea-client-to-streaming-chromecast\"" rules
  && flake.inputs.nixpkgs.lib.hasInfix "iifname \"down-client2\" oifname \"downstr-stream\" accept comment \"allow-sitea-client-to-streaming-chromecast\"" rules
  && !(flake.inputs.nixpkgs.lib.hasInfix "iifname \"downstr-stream\" oifname \"down-client\" accept comment \"allow-sitea-client-to-streaming-chromecast\"" rules)
  && !(flake.inputs.nixpkgs.lib.hasInfix "iifname \"downstr-stream\" oifname \"down-client2\" accept comment \"allow-sitea-client-to-streaming-chromecast\"" rules)
EOF

result="$(
  REPO_ROOT="${repo_root}" \
  INTENT_PATH="${intent_path}" \
  INVENTORY_PATH="${inventory_path}" \
    nix eval \
      --extra-experimental-features 'nix-command flakes' \
      --impure --json --expr "${expr}"
)"

[[ "${result}" == "true" ]]

echo "PASS sitea-streaming-local-relations"
