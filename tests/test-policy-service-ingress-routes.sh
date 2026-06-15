#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${repo_root}/tests/lib/test-common.sh"

example_root="${repo_root}/tests/fixtures/s-router-overlay-dns-lane-policy"
result_json="$(mktemp)"
eval_stderr="$(mktemp)"
trap 'rm -f "${result_json}" "${eval_stderr}"' EXIT

nix_eval_json_or_fail \
  policy-service-ingress-routes \
  "${result_json}" \
  "${eval_stderr}" \
  env REPO_ROOT="${repo_root}" \
    INTENT_PATH="${example_root}/intent.nix" \
    INVENTORY_PATH="${example_root}/inventory-nixos.nix" \
    nix eval \
      --extra-experimental-features 'nix-command flakes' \
      --impure --json \
      --file "${repo_root}/tests/nix/policy-service-ingress-routes.nix"

if ! assert_json_checks_ok policy-service-ingress-routes "${result_json}"; then
  jq -S . "${result_json}" >&2 || true
  exit 1
fi

echo "PASS policy-service-ingress-routes"
