#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${repo_root}/tests/lib/test-common.sh"

example_root="$(flake_input_path network-labs)/examples/s-router-overlay-dns-lane-policy"
intent_path="${example_root}/intent.nix"
inventory_path="${example_root}/inventory-nixos.nix"

result_json="$(mktemp)"
eval_stderr="$(mktemp)"
trap 'rm -f "${result_json}" "${eval_stderr}"' EXIT

nix_eval_json_or_fail \
  routed-gua-no-nat66 \
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
          boxName = "s-router-hetzner-anywhere";
          inherit system;
          intentPath = builtins.getEnv "INTENT_PATH";
          inventoryPath = builtins.getEnv "INVENTORY_PATH";
        };
        cfg = (lib.nixosSystem {
          inherit system;
          modules = [ builtContainers."c-router-core".config ];
        }).config;
        rules = cfg.networking.nftables.ruleset;
      in
      {
        message = "routed hostile GUA must not be NAT66 masqueraded; NAT66 requires explicit CPM intent and is not the default renderer behavior";
        inherit rules;
      }
    '

rules_file="$(mktemp)"
trap 'rm -f "${result_json}" "${eval_stderr}" "${rules_file}"' EXIT

_jq -r '.rules' "${result_json}" >"${rules_file}"

if ! rg -q 'table ip nat' "${rules_file}" || ! rg -q 'oifname "eth0" masquerade' "${rules_file}"; then
  echo "FAIL routed-gua-no-nat66: expected IPv4 egress masquerade to remain rendered for private IPv4 internet egress" >&2
  echo "nft nat excerpt:" >&2
  rg 'table ip|table ip6|postrouting|masquerade' "${rules_file}" >&2 || true
  exit 1
fi

if awk '
  /table ip6 nat/ { in_ip6_nat = 1; next }
  in_ip6_nat && /^  table / { in_ip6_nat = 0 }
  in_ip6_nat && /masquerade/ { found = 1 }
  END { exit found ? 0 : 1 }
' "${rules_file}"; then
  echo "FAIL routed-gua-no-nat66: routed hostile GUA must not be NAT66 masqueraded; NAT66 requires explicit CPM intent and is not the default renderer behavior" >&2
  echo "nft nat excerpt:" >&2
  rg 'table ip|table ip6|postrouting|masquerade' "${rules_file}" >&2 || true
  exit 1
fi

pass "routed-gua-no-nat66"
