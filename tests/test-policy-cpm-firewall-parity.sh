#!/usr/bin/env bash
# GAMP-ID: FS-170-HDS-010-SDS-010
# Verifies CPM modeled deny decisions and renderer nftables output stay in
# parity for the s-router policy fixture.
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${repo_root}/tests/lib/test-common.sh"

example_root="${repo_root}/tests/fixtures/s-router-overlay-dns-lane-policy"
tmp_dir="$(mktemp -d)"
result_json="${tmp_dir}/result.json"
eval_stderr="${tmp_dir}/eval.stderr"
trap 'rm -rf "${tmp_dir}"' EXIT

build_cpm_json \
  "${example_root}/intent.nix" \
  "${example_root}/inventory-nixos.nix" \
  "${tmp_dir}/cpm.json"

nix_eval_json_or_fail \
  policy-cpm-firewall-parity \
  "${result_json}" \
  "${eval_stderr}" \
  env REPO_ROOT="${repo_root}" \
    BOX_NAME="s-router-test" \
    INTENT_PATH="${example_root}/intent.nix" \
    INVENTORY_PATH="${example_root}/inventory-nixos.nix" \
    CPM_PATH="${tmp_dir}/cpm.json" \
    nix eval \
      --extra-experimental-features 'nix-command flakes' \
      --impure --json \
      --file "${repo_root}/tests/nix/policy-forward-default-paths.nix"

if [[ "$(_jq -r '.ok' "${result_json}")" != "true" ]]; then
  echo "FAIL policy-cpm-firewall-parity: failed checks" >&2
  _jq -r '.failed[]' "${result_json}" >&2
  echo "full check state:" >&2
  _jq -S . "${result_json}" >&2
  exit 1
fi

policy_containers="$(_jq -r '.coverage.policyContainerCount' "${result_json}")"
typed_denies="$(_jq -r '.coverage.typedDenyRelationCount' "${result_json}")"
downstream_accepts="$(_jq -r '.coverage.downstreamUplinkAcceptCount' "${result_json}")"

echo "PASS policy-cpm-firewall-parity: policyContainers=${policy_containers} typedDenyRelations=${typed_denies} downstreamUplinkAccepts=${downstream_accepts}"
