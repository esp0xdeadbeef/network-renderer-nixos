#!/usr/bin/env bash
set - euo pipefail

  repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${repo_root}/tests/lib/test-common.sh"

example_root="${repo_root}/tests/fixtures/s-router-overlay-dns-lane-policy"

policy_rules="$(
  REPO_ROOT="${repo_root}" \
  INTENT_PATH="${example_root}/intent.nix" \
  INVENTORY_PATH="${example_root}/inventory-nixos.nix" \
    nix eval \
      --extra-experimental-features 'nix-command flakes' \
      --impure --raw --expr '
        let
          flake = builtins.getFlake ("path:" + builtins.getEnv "REPO_ROOT");
          system = "x86_64-linux";
          hostBuild = import (builtins.getEnv "REPO_ROOT" + "/tests/nix/build-host-from-paths.nix") {
            selector = "s-router-test";
            intentPath = builtins.getEnv "INTENT_PATH";
            inventoryPath = builtins.getEnv "INVENTORY_PATH";
            inherit system;
          };
          container = hostBuild.renderedHost.containers."s-router-policy-only";
          evaluated = flake.inputs.nixpkgs.lib.nixosSystem {
            inherit system;
            modules = [ container.config ];
          };
        in
        evaluated.config.networking.nftables.ruleset
      '
)"

# The current contract is source-scoped: an admitted relation renders an
# accept for each modeled source prefix on the requester lane, and the exit
# lane set is the scope's selection, not every ISP. Derive the client2 prefixes
# from the rendered accepts themselves (so the check follows the model), then
# require the matching DNS leak deny and no unsourced accept.
mapfile -t accept_lines < <(grep -F 'iifname "down-client2"' <<<"${policy_rules}" | grep -F 'accept comment "allow-tenants-to-uplinks"')
((${#accept_lines[@]} > 0)) || fail "client2 public-egress accept rules are missing entirely"

declare -A seen_lane_prefix=()
for line in "${accept_lines[@]}"; do
lane="$(sed -n 's/.*oifname "\([^"]*\)".*/\1/p' <<<"${line}")"
  family="$(sed -n 's/.*\(ip6\? saddr\).*/\1/p' <<<"${line}")"
  prefix="$(sed -n 's/.*ip6\? saddr \([^ ]*\).*/\1/p' <<<"${line}")"
  [[ -n "${lane}" && -n "${prefix}" && -n "${family}" ]] || fail "client2 accept rule is not source- and lane-scoped: ${line}"
  seen_lane_prefix["${lane}|${family}|${prefix}"]=1
done

for key in "${!seen_lane_prefix[@]}"; do
  lane="${key%%|*}"
  rest="${key#*|}"
family="${rest%%|*}"
prefix="${rest#*|}"

grep -F "iifname \"down-client2\" oifname \"${lane}\" ${family} ${prefix} meta l4proto udp udp dport { 53 } drop comment \"deny-sitea-dns-to-uplinks\"" \
<<<"${policy_rules}" >/dev/null \
|| fail "missing client2 UDP DNS leak block for ${prefix} on ${lane}"

grep -F "iifname \"down-client2\" oifname \"${lane}\" ${family} ${prefix} meta l4proto tcp tcp dport { 53 } drop comment \"deny-sitea-dns-to-uplinks\"" \
<<<"${policy_rules}" >/dev/null \
|| fail "missing client2 TCP DNS leak block for ${prefix} on ${lane}"

grep -F "iifname \"down-client2\" oifname \"${lane}\" accept comment \"allow-tenants-to-uplinks\"" \
<<<"${policy_rules}" >/dev/null \
&& fail "client2 accept on ${lane} is not source-scoped (deny-by-default contract)"
done

pass "client2-policy-uplink-firewall"
