#!/usr/bin/env bash
set -euo pipefail
# LAB-SMT-ID: LAB-SMT-013
# LAB-SMT-SCOPE: examples-only; see network-labs/tests/SMT.md

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${repo_root}/tests/lib/test-common.sh"

case_dir="${repo_root}/tests/fixtures/ipv6-pd-downstream-delegation"
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
        builtContainers = import (builtins.getEnv "REPO_ROOT" + "/tests/nix/build-containers-from-paths.nix") {
          boxName = "lab-host";
          system = "x86_64-linux";
        };
        configFor =
          name:
          (flake.inputs.nixpkgs.lib.nixosSystem {
            system = "x86_64-linux";
            modules = [ builtContainers.${name}.config ];
          }).config;
        tenantCheck =
          containerName: tenantName: delegatedLength: tenantLength: slot: sourceFile:
          let
            cfg = configFor containerName;
            service = cfg.systemd.services."radvd-generate-tenant-${tenantName}";
            script = builtins.readFile service.serviceConfig.ExecStart;
            pathConfig = (cfg.systemd.paths."radvd-prefix-tenant-${tenantName}" or { }).pathConfig or { };
            lengthNeedle = "\"${toString delegatedLength}\" \"${toString tenantLength}\" \"${toString slot}\"";
          in
            builtins.match (".*?" + sourceFile + ".*") script != null
            && builtins.match (".*?" + lengthNeedle + ".*") script != null
            && builtins.match ".*?ip -6 route replace.*?\\$pd_prefix.*" script != null
            && (pathConfig.PathExists or null) == sourceFile
            && (pathConfig.PathChanged or null) == sourceFile
            && (pathConfig.Unit or null) == "radvd-generate-tenant-${tenantName}.service";
      in
        # Each delegated allocation is derived from its own provider prefix file
        # (FS-350-HDS-010-SDS-010-SMS-060), so the RA generator and its path unit
        # must follow the tenant source file.
        tenantCheck "s-router-access-client-a" "client-a" 48 64 1 "/run/s88-ipv6-pd/wan-client-a.prefix"
        && tenantCheck "s-router-access-client-b" "client-b" 48 52 1 "/run/s88-ipv6-pd/wan.prefix"
    '

echo "PASS ipv6-pd-downstream-delegation-example"
