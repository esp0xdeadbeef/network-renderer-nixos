#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${repo_root}/tests/lib/test-common.sh"

example_root="$(flake_input_path network-labs)/examples/s-router-overlay-dns-lane-policy"
intent_path="${example_root}/intent.nix"
inventory_path="${example_root}/inventory-nixos.nix"

[[ -f "${intent_path}" ]] || fail "missing intent: ${intent_path}"
[[ -f "${inventory_path}" ]] || fail "missing inventory: ${inventory_path}"

result_json="$(mktemp)"
eval_stderr="$(mktemp)"
trap 'rm -f "${result_json}" "${eval_stderr}"' EXIT

nix_eval_json_or_fail \
  dns-service-access-policy-exceptions \
  "${result_json}" \
  "${eval_stderr}" \
  env REPO_ROOT="${repo_root}" \
    INTENT_PATH="${intent_path}" \
    INVENTORY_PATH="${inventory_path}" \
    nix eval \
    --extra-experimental-features 'nix-command flakes' \
    --impure --json --expr '
      let
        flake = builtins.getFlake ("path:" + builtins.getEnv "REPO_ROOT");
        lib = flake.inputs.nixpkgs.lib;
        builtContainers = flake.lib.containers.buildForBox {
          boxName = "s-router-test";
          system = "x86_64-linux";
          intentPath = builtins.getEnv "INTENT_PATH";
          inventoryPath = builtins.getEnv "INVENTORY_PATH";
        };
        mkCfg = containerName:
          (flake.inputs.nixpkgs.lib.nixosSystem {
            system = "x86_64-linux";
            modules = [ builtContainers.${containerName}.config ];
          }).config;
        accessMgmtRules = (mkCfg "s-router-access-mgmt").networking.nftables.ruleset;
        accessMgmtDnsScript = (mkCfg "s-router-access-mgmt").systemd.services.nft-allow-dns-service.script;
        policyRules = (mkCfg "s-router-policy-only").networking.nftables.ruleset;
        hasDirectDnsDrop = ifName: rules:
          lib.hasInfix "iifname \"${ifName}\" udp dport 53 drop comment \"deny-direct-dns-egress\"" rules
          && lib.hasInfix "iifname \"${ifName}\" tcp dport 53 drop comment \"deny-direct-dns-egress\"" rules;
        checks = {
          intent_has_explicit_mgmt_dns_to_uplink_allow =
            lib.hasInfix "iifname \"downstream-mgmt\" oifname \"up-mgmt-a\" meta l4proto udp udp dport { 53 } accept comment \"allow-mgmt-dns-to-uplinks\"" policyRules
            && lib.hasInfix "iifname \"downstream-mgmt\" oifname \"up-mgmt-b\" meta l4proto tcp tcp dport { 53 } accept comment \"allow-mgmt-dns-to-uplinks\"" policyRules;
          access_mgmt_does_not_preempt_explicit_policy_dns_allow =
            !(hasDirectDnsDrop "tenant-mgmt" accessMgmtRules)
            && !(hasDirectDnsDrop "tenant-mgmt" accessMgmtDnsScript);
          policy_still_blocks_direct_client_dns_to_uplinks =
            lib.hasInfix "iifname \"downstr-client\" oifname \"up-client-a\" meta l4proto udp udp dport { 53 } drop comment \"deny-sitea-dns-to-uplinks\"" policyRules
            && lib.hasInfix "iifname \"downstr-client\" oifname \"up-client-b\" meta l4proto tcp tcp dport { 53 } drop comment \"deny-sitea-dns-to-uplinks\"" policyRules;
        };
      in
      {
        ok = builtins.all (name: checks.${name}) (builtins.attrNames checks);
        failed = builtins.filter (name: !(checks.${name})) (builtins.attrNames checks);
        inherit checks;
      }
    '

assert_json_checks_ok dns-service-access-policy-exceptions "${result_json}"

echo "PASS dns-service-access-policy-exceptions"
