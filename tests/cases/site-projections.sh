#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "${repo_root}/tests/lib/test-common.sh"

labs_root="$(flake_input_path network-labs)"

run_case() {
  local example_name="$1"
  local jq_expr="$2"

  local case_dir="${labs_root}/examples/${example_name}"
  local intent_path="${case_dir}/intent.nix"
  local inventory_path="${case_dir}/inventory-nixos.nix"

  [[ -f "${intent_path}" ]] || fail "missing intent.nix: ${intent_path}"
  [[ -f "${inventory_path}" ]] || fail "missing inventory-nixos.nix: ${inventory_path}"

  local tmp_dir
  tmp_dir="$(mktemp -d "${TMPDIR:-/tmp}/network-renderer-nixos-sites.${example_name}.XXXXXX")"
  trap 'rm -rf "${tmp_dir}"' RETURN

  (
    cd "${tmp_dir}"

    build_cpm_json "${intent_path}" "${inventory_path}" "${tmp_dir}/cpm.json"

    nix run \
      --no-write-lock-file \
      --extra-experimental-features 'nix-command flakes' \
      "${repo_root}"#render-dry-config \
      -- \
      --debug \
      "${tmp_dir}/cpm.json" \
      >/dev/null

    _jq -e "${jq_expr}" ./90-render.json >/dev/null
  )

  trap - RETURN
  rm -rf "${tmp_dir}"

  pass "site-projections:${example_name}"
}

# IPv6 PD plan is site-scoped and must be visible to consumers without guessing.
run_case "single-wan-ipv6-pd" '
  .sites.esp0xdeadbeef["site-a"].ipv6.pd.perTenantPrefixLength == 64
'
run_case "single-wan-ipv6-pd" '
  .sites.esp0xdeadbeef["site-a"].ipv6.tenants.client.mode == "dhcpv6"
'

# Uplink egress routing policy is site-scoped and inventory-driven.
run_case "single-wan-uplink-ebgp" '
  .sites.esp0xdeadbeef["site-a"].routing.uplinks.wan.mode == "bgp"
'

exit 0
