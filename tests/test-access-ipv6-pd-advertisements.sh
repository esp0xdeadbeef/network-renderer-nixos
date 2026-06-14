     1|#!/usr/bin/env bash
     2|set -euo pipefail
     3|
     4|repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
     5|source "${repo_root}/tests/lib/test-common.sh"
     6|
     7|labs_root="$(flake_input_path network-labs)"
     8|intent_path="${labs_root}/examples/single-wan-ipv6-pd/intent.nix"
     9|inventory_path="${labs_root}/examples/single-wan-ipv6-pd/inventory-nixos.nix"
    10|
    11|[[ -f "${intent_path}" ]] || { echo "missing intent: ${intent_path}" >&2; exit 1; }
    12|[[ -f "${inventory_path}" ]] || { echo "missing inventory: ${inventory_path}" >&2; exit 1; }
    13|
    14|nix_eval_true_or_fail "access-ipv6-pd-advertisements" env REPO_ROOT="${repo_root}" \
    15|INTENT_PATH="${intent_path}" \
    16|INVENTORY_PATH="${inventory_path}" \
    17|  nix eval \
    18|    --extra-experimental-features 'nix-command flakes' \
    19|    --impure --expr '
    20|      let
    21|        flake = builtins.getFlake ("path:" + builtins.getEnv "REPO_ROOT");
    22|        builtContainers = import (builtins.getEnv "REPO_ROOT" + "/tests/nix/build-containers-from-paths.nix") {
23|          boxName = "lab-host";
    24|          system = "x86_64-linux";
    25|          intentPath = builtins.getEnv "INTENT_PATH";
    26|          inventoryPath = builtins.getEnv "INVENTORY_PATH";
    27|
};
    28|        cfg =
    29|          (flake.inputs.nixpkgs.lib.nixosSystem {
    30|            system = "x86_64-linux";
    31|            modules = [ builtContainers."s-router-access-client".config ];
    32|          }).config;
    33|        service = cfg.systemd.services."radvd-generate-tenant-client";
    34|        script = builtins.readFile service.serviceConfig.ExecStart;
    35|        pathUnit = cfg.systemd.paths."radvd-prefix-tenant-client" or { };
    36|        pathConfig = pathUnit.pathConfig or { };
    37|      in
    38|        builtins.match ".*?/run/s88-ipv6-pd/wan.prefix.*" script != null
    39|        && builtins.match ".*?\"56\" \"64\" \"1\".*" script != null
    40|        && (pathConfig.PathExists or null) == "/run/s88-ipv6-pd/wan.prefix"
    41|        && (pathConfig.PathChanged or null) == "/run/s88-ipv6-pd/wan.prefix"
    42|        && (pathConfig.Unit or null) == "radvd-generate-tenant-client.service"
    43|    '
    44|
    45|echo "PASS access-ipv6-pd-advertisements"
    46|