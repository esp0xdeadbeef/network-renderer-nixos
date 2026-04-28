#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${repo_root}/tests/lib/test-common.sh"

example_root="$(flake_input_path network-labs)/examples/s-router-test-three-site"

REPO_ROOT="${repo_root}" \
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
        evalContainer = container:
          (flake.inputs.nixpkgs.lib.nixosSystem {
            inherit system;
            modules = [ container.config ];
          }).config;
        rules = (evalContainer builtContainers."b-router-policy").networking.nftables.ruleset;
        siteCRules = (evalContainer builtContainers."c-router-policy").networking.nftables.ruleset;
        branchDownstreamRules =
          (evalContainer builtContainers."b-router-downstream-selector").networking.nftables.ruleset;
        siteCDownstreamRules =
          (evalContainer builtContainers."c-router-downstream-selector").networking.nftables.ruleset;
        siteCUpstreamRules =
          (evalContainer builtContainers."c-router-upstream-selector").networking.nftables.ruleset;
        has = flake.inputs.nixpkgs.lib.hasInfix;
        hasBefore =
          earlier: later: text:
          has later text && has earlier (builtins.elemAt (builtins.split later text) 0);
      in
        has "type filter hook input priority filter; policy drop;" rules
        && has "iifname \"lo\" accept" rules
        && has "ct state established,related accept" rules
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
        && hasBefore
          "allow-sitec-printer-nebula-underlay-to-wan"
          "deny-sitec-printer-to-wan"
          siteCRules
        && hasBefore
          "allow-sitec-nas-nebula-underlay-to-wan"
          "deny-sitec-nas-to-wan"
          siteCRules
        && has "type filter hook forward priority filter; policy drop;" branchDownstreamRules
        && !(has "iifname \"access-branch\" oifname \"access-hostile\" accept" branchDownstreamRules)
        && !(has "iifname \"access-hostile\" oifname \"access-branch\" accept" branchDownstreamRules)
        && !(has "iifname \"policy-branch\" oifname \"policy-hostile\" accept" branchDownstreamRules)
        && !(has "iifname \"access-nas\" oifname \"access-printer\" accept" siteCDownstreamRules)
        && !(has "iifname \"access-printer\" oifname \"access-nas\" accept" siteCDownstreamRules)
        && !(has "iifname \"pol-nas-wan\" oifname \"pol-prn-wan\" accept" siteCUpstreamRules)
        && !(has "iifname \"pol-prn-wan\" oifname \"pol-nas-wan\" accept" siteCUpstreamRules)
    ' | grep -qx true

echo "PASS policy-zone-firewall-scoping"
