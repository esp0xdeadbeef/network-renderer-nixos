#!/usr/bin/env bash
# GAMP-ID: FS-320-HDS-010-SDS-010-SMS-010
# GAMP-SCOPE: software-module-test
# Behavioral proof for NixOS renderer layout preservation on a compact,
# co-located access layout with distinct policy identities.
set -euo pipefail

repo_root="${SMS_TEST_REPO_ROOT:-$(git -C "$(dirname "${BASH_SOURCE[0]}")" rev-parse --show-toplevel)}"
source "${repo_root}/tests/lib/test-common.sh"

tmp_dir="$(mktemp -d)"
trap 'rm -rf "${tmp_dir}"' EXIT

result_json="${tmp_dir}/fs320-layout-preservation.json"
stderr_file="${tmp_dir}/fs320-layout-preservation.stderr"

nix_eval_json_or_fail \
  "FS-320-HDS-010-SDS-010-SMS-010 layout preservation" \
  "${result_json}" \
  "${stderr_file}" \
  env REPO_ROOT="${repo_root}" \
    nix eval \
      --extra-experimental-features 'nix-command flakes' \
      --impure --json \
      --file "${repo_root}/tests/nix/fs320-hds010-sds010-sms010-layout-preservation.nix"

assert_json_checks_ok "FS-320-HDS-010-SDS-010-SMS-010 layout preservation" "${result_json}"

containers="$(_jq -r '.coverage.containerCount' "${result_json}")"
interfaces="$(_jq -r '.coverage.coLocatedTenantInterfaces' "${result_json}")"
rules="$(_jq -r '.coverage.explicitForwardingRules' "${result_json}")"
negatives="$(_jq -r '.coverage.seededNegativeCount' "${result_json}")"

echo "PASS FS-320-HDS-010-SDS-010-SMS-010 layout preservation: containers=${containers} coLocatedTenantInterfaces=${interfaces} explicitForwardingRules=${rules} seededNegatives=${negatives}"
