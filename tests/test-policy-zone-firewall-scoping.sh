#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${repo_root}/tests/lib/test-common.sh"

example_root="$(flake_input_path network-labs)/examples/s-router-overlay-dns-lane-policy"

nix_eval_true_or_fail "policy-zone-firewall-scoping" env REPO_ROOT="${repo_root}" \
INTENT_PATH="${example_root}/intent.nix" \
INVENTORY_PATH="${example_root}/inventory-nixos.nix" \
  nix eval \
    --extra-experimental-features 'nix-command flakes' \
    --impure --expr '
      let
        flake = builtins.getFlake ("path:" + builtins.getEnv "REPO_ROOT");
        system = "x86_64-linux";
        builtContainers = flake.lib.containers.buildForBox {
          boxName = "s-router-test";
          inherit system;
          intentPath = builtins.getEnv "INTENT_PATH";
          inventoryPath = builtins.getEnv "INVENTORY_PATH";
        };
        siteCContainers = flake.lib.containers.buildForBox {
          boxName = "s-router-hetzner-anywhere";
          inherit system;
          intentPath = builtins.getEnv "INTENT_PATH";
          inventoryPath = builtins.getEnv "INVENTORY_PATH";
        };
        evalContainer = container:
          (flake.inputs.nixpkgs.lib.nixosSystem {
            inherit system;
            modules = [ container.config ];
          }).config;
        rules = (evalContainer builtContainers."b-router-policy").networking.nftables.ruleset;
        siteCRules = (evalContainer siteCContainers."c-router-policy").networking.nftables.ruleset;
        branchDownstreamRules =
          (evalContainer builtContainers."b-router-downstream-selector").networking.nftables.ruleset;
        siteCDownstreamRules =
          (evalContainer siteCContainers."c-router-downstream-selector").networking.nftables.ruleset;
        siteCUpstreamRules =
          (evalContainer siteCContainers."c-router-upstream-selector").networking.nftables.ruleset;
        has = flake.inputs.nixpkgs.lib.hasInfix;
        hasBefore =
          earlier: later: text:
          has later text && has earlier (builtins.elemAt (builtins.split later text) 0);
      in
        has "type filter hook input priority filter; policy drop;" rules
        && has "iifname \"lo\" accept" rules
        && has "ct state established,related accept" rules
        && has "icmpv6 type { nd-neighbor-solicit, nd-neighbor-advert, nd-router-solicit, nd-router-advert } accept comment \"allow-ipv6-nd-ra\"" rules
        && has "iifname \"downstr-hostile\" oifname \"up-hostile-ew\" meta l4proto udp udp dport { 53 } accept comment \"allow-hostile-dns-to-east-west\"" rules
        && has "iifname \"downstr-hostile\" oifname \"up-hostile-ew\" accept comment \"allow-hostile-to-east-west\"" rules
        && has "iifname \"up-hostile-ew\" oifname \"downstr-hostile\" accept comment \"allow-east-west-to-hostile\"" rules
        && has "iifname \"downstr-branch\" oifname \"up-branch-ew\" accept comment \"allow-branch-to-east-west\"" rules
        && has "iifname \"downstr-branch\" oifname \"upstream-branch\" accept comment \"allow-branch-to-wan\"" rules
        && has "iifname \"downstr-hostile\" oifname \"up-hostile\" accept comment \"allow-hostile-to-wan\"" rules
        && !(has "iifname \"downstr-hostile\" oifname \"up-hostile-ew\" accept comment \"allow-hostile-to-wan\"" rules)
        && !(has "iifname \"downstr-branch\" oifname \"up-branch-ew\" accept comment \"allow-branch-to-wan\"" rules)
        && !(has "iifname \"downstr-hostile\" oifname \"up-hostile-ew\" meta l4proto udp udp dport { 53 } drop comment \"deny-hostile-dns-to-wan\"" rules)
        && !(has "iifname \"downstr-branch\" oifname \"up-branch-ew\" meta l4proto udp udp dport { 53 } drop comment \"deny-branch-dns-to-wan\"" rules)
        && !(has "iifname \"downstr-hostile\" oifname \"upstream-branch\" accept comment \"allow-hostile-to-wan\"" rules)
        && !(has "iifname \"downstr-hostile\" oifname \"up-branch-ew\" accept comment \"allow-hostile-to-wan\"" rules)
        && !(has "iifname \"downstr-hostile\" oifname \"up-branch-ew\" accept comment \"allow-hostile-to-east-west\"" rules)
        && !(has "iifname \"up-branch-ew\" oifname \"downstr-hostile\" accept comment \"allow-east-west-to-hostile\"" rules)
        && !(has "iifname \"downstr-branch\" oifname \"up-hostile\" accept comment \"allow-branch-to-wan\"" rules)
        && !(has "iifname \"downstr-branch\" oifname \"up-hostile-ew\" accept comment \"allow-branch-to-wan\"" rules)
        && has "iifname \"downstream-dmz\" oifname \"up-dmz-wan\" accept comment \"allow-sitec-dmz-to-wan\"" siteCRules
        && has "iifname \"downstr-client\" oifname \"up-client-wan\" accept comment \"allow-sitec-client-to-wan\"" siteCRules
        && has "iifname \"downstr-client\" oifname \"downstream-dmz\" meta l4proto udp udp dport { 53 } accept comment \"allow-sitec-client-to-dmz-dns\"" siteCRules
        && has "iifname \"downstr-client\" oifname \"up-client-wan\" meta l4proto udp udp dport { 53 } drop comment \"deny-sitec-client-dns-to-wan\"" siteCRules
        && has "iifname \"downstr-client\" oifname \"up-client-ew\" accept comment \"allow-sitec-client-to-east-west\"" siteCRules
        && has "iifname \"up-client-ew\" oifname \"downstr-client\" accept comment \"allow-east-west-to-sitec-client\"" siteCRules
        && has "type filter hook forward priority filter; policy drop;" branchDownstreamRules
        && !(has "iifname \"access-branch\" oifname \"access-hostile\" accept" branchDownstreamRules)
        && !(has "iifname \"access-hostile\" oifname \"access-branch\" accept" branchDownstreamRules)
        && !(has "iifname \"policy-branch\" oifname \"policy-hostile\" accept" branchDownstreamRules)
        && !(has "iifname \"access-dmz\" oifname \"access-client\" accept" siteCDownstreamRules)
        && !(has "iifname \"access-client\" oifname \"access-dmz\" accept" siteCDownstreamRules)
        && !(has "iifname \"policy-client-wan\" oifname \"policy-dmz-wan\" accept" siteCUpstreamRules)
        && !(has "iifname \"policy-dmz-wan\" oifname \"policy-client-wan\" accept" siteCUpstreamRules)
    '

echo "PASS policy-zone-firewall-scoping"
