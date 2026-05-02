#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

intent_path="/home/deadbeef/github/network-labs/examples/single-wan-ipv6-pd/intent.nix"
inventory_path="/home/deadbeef/github/network-labs/examples/single-wan-ipv6-pd/inventory-nixos.nix"

[[ -f "${intent_path}" ]] || { echo "missing intent: ${intent_path}" >&2; exit 1; }
[[ -f "${inventory_path}" ]] || { echo "missing inventory: ${inventory_path}" >&2; exit 1; }

nix_eval_true_or_fail "access-ipv6-pd-advertisements" env REPO_ROOT="${repo_root}" \
INTENT_PATH="${intent_path}" \
INVENTORY_PATH="${inventory_path}" \
  nix eval \
    --extra-experimental-features 'nix-command flakes' \
    --impure --expr '
      let
        flake = builtins.getFlake ("path:" + builtins.getEnv "REPO_ROOT");
        builtContainers = flake.lib.containers.buildForBox {
          boxName = "lab-host";
          system = "x86_64-linux";
          intentPath = builtins.getEnv "INTENT_PATH";
          inventoryPath = builtins.getEnv "INVENTORY_PATH";
        };
        cfg =
          (flake.inputs.nixpkgs.lib.nixosSystem {
            system = "x86_64-linux";
            modules = [ builtContainers."s-router-access-client".config ];
          }).config;
        service = cfg.systemd.services."radvd-generate-tenant-client";
        script = builtins.readFile service.serviceConfig.ExecStart;
        pathUnit = cfg.systemd.paths."radvd-prefix-tenant-client" or { };
        pathConfig = pathUnit.pathConfig or { };
      in
        builtins.match ".*?/run/s88-ipv6-pd/wan.prefix.*" script != null
        && builtins.match ".*?\"56\" \"64\" \"1\".*" script != null
        && (pathConfig.PathExists or null) == "/run/s88-ipv6-pd/wan.prefix"
        && (pathConfig.PathChanged or null) == "/run/s88-ipv6-pd/wan.prefix"
        && (pathConfig.Unit or null) == "radvd-generate-tenant-client.service"
    '

echo "PASS access-ipv6-pd-advertisements"
