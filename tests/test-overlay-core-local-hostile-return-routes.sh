#!/usr/bin/env bash
set -euo pipefail
# GAMP-ID: FS-460-HDS-010-SDS-010-SMS-050
# GAMP-ID: FS-370-HDS-010-SDS-010-SMS-120
# LAB-SMT-ID: LAB-SMT-011
# LAB-SMT-SCOPE: examples-only; see network-labs/tests/SMT.md

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${repo_root}/tests/lib/test-common.sh"

# FS-460: the overlay core (site-b's b-router-core-nebula) must keep the local
# hostile tenant's return path. The overlay terminates there, the tenant owns a
# runtime delegated prefix, and the return route is a runtime install (the
# prefix only exists after the source file is read) — both in the policy table
# the hostile prefixes are scoped to and in the main table, via the modeled
# upstream next hop.
example_root="${repo_root}/tests/fixtures/s-router-overlay-dns-lane-policy"

tmp_dir="$(mktemp -d)"
trap 'rm -rf "${tmp_dir}"' EXIT
result_json="${tmp_dir}/overlay-core.json"
stderr_json="${tmp_dir}/overlay-core.err"

nix_eval_json_or_fail \
  overlay-core-local-hostile-return-routes \
  "${result_json}" \
  "${stderr_json}" \
  env REPO_ROOT="${repo_root}" \
    INTENT_PATH="${example_root}/intent.nix" \
    INVENTORY_PATH="${example_root}/inventory-nixos.nix" \
    nix eval \
      --extra-experimental-features 'nix-command flakes' \
      --impure --json \
      --expr "import ${repo_root}/tests/nix/fs460-overlay-core-hostile-return-routes.nix"

assert_json_checks_ok overlay-core-local-hostile-return-routes "${result_json}"

pass "overlay-core-local-hostile-return-routes"
