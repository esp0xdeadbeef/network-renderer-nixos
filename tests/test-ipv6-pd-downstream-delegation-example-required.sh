#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${repo_root}/tests/lib/test-common.sh"

labs_root="$(flake_input_path network-labs)"
case_dir="${labs_root}/examples/ipv6-pd-downstream-delegation"
intent_path="${case_dir}/intent.nix"
inventory_path="${case_dir}/inventory-nixos.nix"

[[ -f "${intent_path}" ]] || fail "missing intent.nix: ${intent_path}"
[[ -f "${inventory_path}" ]] || fail "missing inventory-nixos.nix: ${inventory_path}"

nix_eval_true_or_fail "ipv6-pd-downstream-delegation-example" env REPO_ROOT="${repo_root}" \
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
        configFor =
          name:
          (flake.inputs.nixpkgs.lib.nixosSystem {
            system = "x86_64-linux";
            modules = [ builtContainers.${name}.config ];
          }).config;
        tenantCheck =
          containerName: tenantName: delegatedLength: tenantLength: slot:
          let
            cfg = configFor containerName;
            service = cfg.systemd.services."radvd-generate-tenant-${tenantName}";
            script = builtins.readFile service.serviceConfig.ExecStart;
            pathConfig = (cfg.systemd.paths."radvd-prefix-tenant-${tenantName}" or { }).pathConfig or { };
            sourceFile = "/run/s88-ipv6-pd/wan.prefix";
            lengthNeedle = "\"${toString delegatedLength}\" \"${toString tenantLength}\" \"${toString slot}\"";
          in
            builtins.match ".*?/run/s88-ipv6-pd/wan.prefix.*" script != null
            && builtins.match (".*?" + lengthNeedle + ".*") script != null
            && builtins.match ".*?ip -6 route replace.*?\\$pd_prefix.*" script != null
            && (pathConfig.PathExists or null) == sourceFile
            && (pathConfig.PathChanged or null) == sourceFile
            && (pathConfig.Unit or null) == "radvd-generate-tenant-${tenantName}.service";
      in
        tenantCheck "s-router-access-client-a" "client-a" 48 64 1
        && tenantCheck "s-router-access-client-b" "client-b" 48 52 1
    '

echo "PASS ipv6-pd-downstream-delegation-example"
