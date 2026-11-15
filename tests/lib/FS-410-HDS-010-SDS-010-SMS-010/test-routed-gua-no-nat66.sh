#!/usr/bin/env bash
# GAMP-ID: FS-410-HDS-010-SDS-010-SMS-010
set -euo pipefail
# LAB-SMT-ID: LAB-SMT-018
# LAB-SMT-SCOPE: examples-only; see network-labs/tests/SMT.md

repo_root="${SMS_TEST_REPO_ROOT:-$(git -C "$(dirname "${BASH_SOURCE[0]}")" rev-parse --show-toplevel)}"
source "${repo_root}/tests/lib/test-common.sh"

example_root="${repo_root}/tests/fixtures/s-router-overlay-dns-lane-policy"
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
        builtContainers = import (builtins.getEnv "REPO_ROOT" + "/tests/nix/build-containers-from-paths.nix") {
          boxName = "s-router-hetzner-anywhere";
          inherit system;
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

# Non-vacuity: the negative NAT assertions below would also hold on an empty or
# partially rendered ruleset, so prove the core's base table and forward chain
# were rendered before reading them as "the routed GUA is not NAT66'd".
if ! rg -q 'table inet router' "${rules_file}" || ! rg -q 'chain forward' "${rules_file}"; then
  echo "FAIL routed-gua-no-nat66: the core ruleset is missing its base table/forward chain; an empty render cannot prove the NAT66 boundary" >&2
  sed -n '1,20p' "${rules_file}" >&2
  exit 1
fi

# FS-420: translation is a modeled selection, not a renderer default. This
# fixture selects none for site-c, so the core must render no NAT44 either. The
# positive NAT44/NAT66 control is FS-400-HDS-010-SDS-010-SMS-060 against
# network-labs/examples/single-wan, which declares translation explicitly; this
# case owns only the "routed GUA is not NAT66'd" boundary.
if rg -q 'oifname "[^"]+" ip saddr .*masquerade' "${rules_file}"; then
  echo "FAIL routed-gua-no-nat66: IPv4 masquerade was rendered although the model selected no translation (FS-420: renderer-local defaults shall not create translation behavior absent from the bundle)" >&2
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
