#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${repo_root}/tests/lib/test-common.sh"

example_root="$(flake_input_path network-labs)/examples/single-wan"
intent_path="${example_root}/intent.nix"
inventory_path="${example_root}/inventory-clab.nix"

result_json="$(mktemp)"
eval_stderr="$(mktemp)"
rules_file="$(mktemp)"
trap 'rm -f "${result_json}" "${eval_stderr}" "${rules_file}"' EXIT

nix_eval_json_or_fail \
  core-ipv6-nat-rendering \
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
        system = "x86_64-linux";
        builtContainers = flake.lib.containers.buildForBox {
          boxName = "s-router-test";
          inherit system;
          intentPath = builtins.getEnv "INTENT_PATH";
          inventoryPath = builtins.getEnv "INVENTORY_PATH";
        };
        cfg = (lib.nixosSystem {
          inherit system;
          modules = [ builtContainers."s-router-core-wan".config ];
        }).config;
      in {
        rules = cfg.networking.nftables.ruleset;
      }
    '

_jq -r '.rules' "${result_json}" >"${rules_file}"

if ! rg -q 'table ip nat' "${rules_file}" || ! rg -q 'oifname "eth0" masquerade' "${rules_file}"; then
  echo "FAIL core-ipv6-nat-rendering: expected IPv4 NAT on rendered WAN eth0" >&2
  rg 'table ip|table ip6|postrouting|masquerade' "${rules_file}" >&2 || true
  exit 1
fi

if ! rg -q 'table ip6 nat' "${rules_file}" || ! rg -q 'oifname "eth0" masquerade' "${rules_file}"; then
  echo "FAIL core-ipv6-nat-rendering: expected IPv6 NAT on rendered WAN eth0 when CPM natIntent.families.ipv6 is true" >&2
  rg 'table ip|table ip6|postrouting|masquerade' "${rules_file}" >&2 || true
  exit 1
fi

scoped_rules="$(
  nix eval --raw --extra-experimental-features 'nix-command flakes' --impure --expr '
    let
      flake = builtins.getFlake ("path:" + toString ./.);
      renderRuleset = import ./s88/ControlModule/firewall/emission/render-ruleset.nix {
        lib = flake.inputs.nixpkgs.lib;
      };
    in
      renderRuleset {
        nat6Interfaces = [ "eth0" ];
        nat6SourcePrefixes = [ "fd42:dead:feed:10::/64" ];
      }
  '
)"

if ! grep -Fq 'oifname "eth0" ip6 saddr fd42:dead:feed:10::/64 masquerade' <<<"${scoped_rules}"; then
  echo "FAIL core-ipv6-nat-rendering: explicit IPv6 NAT source prefixes must scope NAT66" >&2
  printf "%s\n" "${scoped_rules}" >&2
  exit 1
fi

if grep -Fq 'oifname "eth0" masquerade' <<<"${scoped_rules}"; then
  echo "FAIL core-ipv6-nat-rendering: source-scoped NAT66 must not also emit unscoped masquerade" >&2
  rg 'table ip|table ip6|postrouting|masquerade' "${rules_file}" >&2 || true
  exit 1
fi

pass "core-ipv6-nat-rendering"
