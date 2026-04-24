#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

source "${repo_root}/tests/lib/test-common.sh"

search_root="$(flake_input_path network-labs)/examples"

case_dir="${search_root}/dual-wan-branch-overlay"
intent_path="${case_dir}/intent.nix"
inventory_path="${case_dir}/inventory-nixos.nix"

[[ -f "${intent_path}" ]] || fail "missing intent.nix: ${intent_path}"
[[ -f "${inventory_path}" ]] || fail "missing inventory-nixos.nix: ${inventory_path}"

tmp_dir="$(mktemp -d "${TMPDIR:-/tmp}/network-renderer-nixos-missing-wan-map.XXXXXX")"
trap 'rm -rf "${tmp_dir}"' EXIT

(
  cd "${tmp_dir}"
  cat > "${tmp_dir}/inventory-missing-wan-group.nix" <<EOF
let
  base = import ${inventory_path};
in
base
// {
  deployment =
    base.deployment
    // {
      hosts =
        base.deployment.hosts
        // {
          lab-host =
            base.deployment.hosts.lab-host
            // {
              wanGroupToUplink = builtins.removeAttrs
                (base.deployment.hosts.lab-host.wanGroupToUplink or { })
                [ "enterpriseB::site-b::b-router-core" ];
            };
        };
    };
}
EOF

  build_cpm_json "${intent_path}" "${tmp_dir}/inventory-missing-wan-group.nix" "${tmp_dir}/cpm.json"

  set +e
  nix run \
    --no-write-lock-file \
    --extra-experimental-features 'nix-command flakes' \
    "${repo_root}"#render-dry-config \
    -- \
    --debug \
    "${tmp_dir}/cpm.json" \
    >/dev/null \
    2>"${tmp_dir}/render.stderr"
  rc=$?
  set -e

  [[ "${rc}" -ne 0 ]] || fail "expected missing WAN assignment render failure"
  grep -F "strict rendering requires explicit WAN uplink assignment for host 'lab-host'" "${tmp_dir}/render.stderr" >/dev/null \
    || fail "missing strict WAN assignment failure"
  grep -F '"enterpriseB::site-b::b-router-core"' "${tmp_dir}/render.stderr" >/dev/null \
    || fail "missing expected WAN group name in failure output"
)

pass "missing-wan-group-assignment"
