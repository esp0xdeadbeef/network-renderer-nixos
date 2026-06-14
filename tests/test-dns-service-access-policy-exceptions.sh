     1|#!/usr/bin/env bash
     2|set -euo pipefail
     3|
     4|repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
     5|source "${repo_root}/tests/lib/test-common.sh"
     6|
     7|example_root="$(flake_input_path network-labs)/examples/s-router-overlay-dns-lane-policy"
     8|intent_path="${example_root}/intent.nix"
     9|inventory_path="${example_root}/inventory-nixos.nix"
    10|
    11|[[ -f "${intent_path}" ]] || fail "missing intent: ${intent_path}"
    12|[[ -f "${inventory_path}" ]] || fail "missing inventory: ${inventory_path}"
    13|
    14|result_json="$(mktemp)"
    15|eval_stderr="$(mktemp)"
    16|trap 'rm -f "${result_json}" "${eval_stderr}"' EXIT
    17|
    18|nix_eval_json_or_fail \
    19|  dns-service-access-policy-exceptions \
    20|  "${result_json}" \
    21|  "${eval_stderr}" \
    22|  env REPO_ROOT="${repo_root}" \
    23|    INTENT_PATH="${intent_path}" \
    24|    INVENTORY_PATH="${inventory_path}" \
    25|    nix eval \
    26|    --extra-experimental-features 'nix-command flakes' \
    27|    --impure --json --expr '
    28|      let
    29|        flake = builtins.getFlake ("path:" + builtins.getEnv "REPO_ROOT");
    30|        lib = flake.inputs.nixpkgs.lib;
    31|        builtContainers = import (builtins.getEnv "REPO_ROOT" + "/tests/nix/build-containers-from-paths.nix") {
32|          boxName = "s-router-test";
    33|          system = "x86_64-linux";
    34|          intentPath = builtins.getEnv "INTENT_PATH";
    35|          inventoryPath = builtins.getEnv "INVENTORY_PATH";
    36|
};
    37|        mkCfg = containerName:
    38|          (flake.inputs.nixpkgs.lib.nixosSystem {
    39|            system = "x86_64-linux";
    40|            modules = [ builtContainers.${containerName}.config ];
    41|          }).config;
    42|        accessMgmtRules = (mkCfg "s-router-access-mgmt").networking.nftables.ruleset;
    43|        accessMgmtDnsScript = (mkCfg "s-router-access-mgmt").systemd.services.nft-allow-dns-service.script;
    44|        policyRules = (mkCfg "s-router-policy-only").networking.nftables.ruleset;
    45|        hasDirectDnsDrop = ifName: rules:
    46|          lib.hasInfix "iifname \"${ifName}\" udp dport 53 drop comment \"deny-direct-dns-egress\"" rules
    47|          && lib.hasInfix "iifname \"${ifName}\" tcp dport 53 drop comment \"deny-direct-dns-egress\"" rules;
    48|        checks = {
    49|          intent_has_explicit_mgmt_dns_to_uplink_allow =
    50|            lib.hasInfix "iifname \"downstream-mgmt\" oifname \"up-mgmt-a\" meta l4proto udp udp dport { 53 } accept comment \"allow-mgmt-dns-to-uplinks\"" policyRules
    51|            && lib.hasInfix "iifname \"downstream-mgmt\" oifname \"up-mgmt-b\" meta l4proto tcp tcp dport { 53 } accept comment \"allow-mgmt-dns-to-uplinks\"" policyRules;
    52|          access_mgmt_does_not_preempt_explicit_policy_dns_allow =
    53|            !(hasDirectDnsDrop "tenant-mgmt" accessMgmtRules)
    54|            && !(hasDirectDnsDrop "tenant-mgmt" accessMgmtDnsScript);
    55|          policy_still_blocks_direct_client_dns_to_uplinks =
    56|            lib.hasInfix "iifname \"down-client\" oifname \"up-client-a\" meta l4proto udp udp dport { 53 } drop comment \"deny-sitea-dns-to-uplinks\"" policyRules
    57|            && lib.hasInfix "iifname \"down-client\" oifname \"up-client-b\" meta l4proto tcp tcp dport { 53 } drop comment \"deny-sitea-dns-to-uplinks\"" policyRules;
    58|        };
    59|      in
    60|      {
    61|        ok = builtins.all (name: checks.${name}) (builtins.attrNames checks);
    62|        failed = builtins.filter (name: !(checks.${name})) (builtins.attrNames checks);
    63|        inherit checks;
    64|      }
    65|    '
    66|
    67|assert_json_checks_ok dns-service-access-policy-exceptions "${result_json}"
    68|
    69|echo "PASS dns-service-access-policy-exceptions"
    70|