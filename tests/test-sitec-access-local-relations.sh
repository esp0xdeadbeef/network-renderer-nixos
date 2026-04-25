#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

intent_path="/home/deadbeef/github/nixos/nixos/virtual-machine/nixos-shell-vm/s-router-test/intent.nix"
inventory_path="/home/deadbeef/github/nixos/nixos/virtual-machine/nixos-shell-vm/s-router-test/inventory.nix"

[[ -f "${intent_path}" ]] || { echo "missing intent: ${intent_path}" >&2; exit 1; }
[[ -f "${inventory_path}" ]] || { echo "missing inventory: ${inventory_path}" >&2; exit 1; }

read -r -d '' expr <<'EOF' || true
let
  repoRoot = "path:" + builtins.getEnv "REPO_ROOT";
  intentPath = builtins.getEnv "INTENT_PATH";
  inventoryPath = builtins.getEnv "INVENTORY_PATH";
  flake = builtins.getFlake repoRoot;
  system = builtins.currentSystem;
  hostBuild = flake.lib.renderer.buildHostFromPaths {
    selector = "s-router-test";
    inherit system intentPath inventoryPath;
  };
  rendered = hostBuild.renderedHost;
  mediaCfg =
    (flake.inputs.nixpkgs.lib.nixosSystem {
      inherit system;
      modules = [ rendered.containers."c-router-access-media".config ];
    }).config;
  rules = mediaCfg.networking.nftables.ruleset;
in
  builtins.substring 0 0 "" == ""
  && flake.inputs.nixpkgs.lib.hasInfix "iifname \"tenant-users\" oifname \"tenant-streami\" accept comment \"allow-sitec-home-to-local-services\"" rules
  && !(flake.inputs.nixpkgs.lib.hasInfix "iifname \"tenant-streami\" oifname \"tenant-users\" accept comment \"allow-sitec-home-to-local-services\"" rules)
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

echo "PASS sitec-access-local-relations"
