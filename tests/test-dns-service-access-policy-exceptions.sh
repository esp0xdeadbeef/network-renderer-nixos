#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${repo_root}/tests/lib/test-common.sh"

example_root="${repo_root}/tests/fixtures/s-router-overlay-dns-lane-policy"
intent_path="${example_root}/intent.nix"
inventory_path="${example_root}/inventory-nixos.nix"

[[ -f "${intent_path}" ]] || fail "missing intent: ${intent_path}"
[[ -f "${inventory_path}" ]] || fail "missing inventory: ${inventory_path}"

access_rules_json="$(mktemp)"
policy_rules_json="$(mktemp)"
result_json="$(mktemp)"
eval_stderr="$(mktemp)"
trap 'rm -f "${access_rules_json}" "${policy_rules_json}" "${result_json}" "${eval_stderr}"' EXIT

# Each container is evaluated in its own expression: two nixosSystem evaluations
# in one expression recurse deeper than Nix's eval stack allows here, and the
# assertions do not need them in one derivation.
nix_eval_json_or_fail \
  dns-service-access-policy-exceptions-access \
  "${access_rules_json}" \
  "${eval_stderr}" \
  env REPO_ROOT="${repo_root}" \
    INTENT_PATH="${intent_path}" \
    INVENTORY_PATH="${inventory_path}" \
    nix eval \
    --extra-experimental-features 'nix-command flakes' \
    --impure --json --expr '
      let
        flake = builtins.getFlake ("path:" + builtins.getEnv "REPO_ROOT");
        builtContainers = import (builtins.getEnv "REPO_ROOT" + "/tests/nix/build-containers-from-paths.nix") {
          boxName = "s-router-test";
          system = "x86_64-linux";
        };
        mkCfg = containerName:
          (flake.inputs.nixpkgs.lib.nixosSystem {
            system = "x86_64-linux";
            modules = [ builtContainers.${containerName}.config ];
          }).config;
      in
      { accessMgmtRules = (mkCfg "s-router-access-mgmt").networking.nftables.ruleset; }
    '

nix_eval_json_or_fail \
  dns-service-access-policy-exceptions-policy \
  "${policy_rules_json}" \
  "${eval_stderr}" \
  env REPO_ROOT="${repo_root}" \
    INTENT_PATH="${intent_path}" \
    INVENTORY_PATH="${inventory_path}" \
    nix eval \
    --extra-experimental-features 'nix-command flakes' \
    --impure --json --expr '
      let
        flake = builtins.getFlake ("path:" + builtins.getEnv "REPO_ROOT");
        builtContainers = import (builtins.getEnv "REPO_ROOT" + "/tests/nix/build-containers-from-paths.nix") {
          boxName = "s-router-test";
          system = "x86_64-linux";
        };
        mkCfg = containerName:
          (flake.inputs.nixpkgs.lib.nixosSystem {
            system = "x86_64-linux";
            modules = [ builtContainers.${containerName}.config ];
          }).config;
      in
      { policyRules = (mkCfg "s-router-policy-only").networking.nftables.ruleset; }
    '

jq -s '
  (.[0].accessMgmtRules) as $access
  | (.[1].policyRules) as $policy
  | def hasDirectDnsDrop($ifName; $rules):
      ($rules | contains("iifname \"" + $ifName + "\" udp dport 53 drop comment \"deny-direct-dns-egress\""))
      and ($rules | contains("iifname \"" + $ifName + "\" tcp dport 53 drop comment \"deny-direct-dns-egress\""));
  # The rendered rule carries a modeled source match between the interface pair
  # and the transport match, so assert the interface pair and the verdict/comment
  # rather than the whole line text.
  def hasDnsRule($rules; $ifName; $outName; $proto; $verdict; $comment):
      ($rules | contains("iifname \"" + $ifName + "\" oifname \"" + $outName + "\""))
      and ($rules | contains($proto + " dport { 53 } " + $verdict + " comment \"" + $comment + "\""));
  {
    checks: {
      intent_has_explicit_mgmt_dns_to_uplink_allow:
        (hasDnsRule($policy; "downstream-mgmt"; "up-mgmt-a"; "udp"; "accept"; "allow-mgmt-dns-to-uplinks")
        and hasDnsRule($policy; "downstream-mgmt"; "up-mgmt-b"; "tcp"; "accept"; "allow-mgmt-dns-to-uplinks")),
      access_mgmt_does_not_preempt_explicit_policy_dns_allow:
        (hasDirectDnsDrop("tenant-mgmt"; $access) | not),
      # FS-322: the client access scope models its exits explicitly (WAN isp-a
      # and the east-west overlay), so those are the lanes the deny must cover.
      policy_still_blocks_direct_client_dns_to_uplinks:
        (hasDnsRule($policy; "down-client"; "up-client-a"; "udp"; "drop"; "deny-sitea-dns-to-uplinks")
        and hasDnsRule($policy; "down-client"; "up-cli-ew"; "tcp"; "drop"; "deny-sitea-dns-to-uplinks"))
    }
  }
  | . + {
      ok: (all(.checks[]; .)),
      failed: ([.checks | to_entries[] | select(.value == false) | .key])
    }
' "${access_rules_json}" "${policy_rules_json}" > "${result_json}"

assert_json_checks_ok dns-service-access-policy-exceptions "${result_json}"

echo "PASS dns-service-access-policy-exceptions"
