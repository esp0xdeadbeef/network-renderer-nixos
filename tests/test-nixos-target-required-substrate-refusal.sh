#!/usr/bin/env bash
set -euo pipefail
# GAMP-ID: USR-MODEL-001-FS-001-HDS-002-SDS-001-002-SMS-001
# GAMP-ID: USR-MODEL-001-FS-001-HDS-002-SDS-001-002-SMS-001-CMC-001

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

source "${repo_root}/tests/lib/test-common.sh"

tmp_dir="$(mktemp -d "${TMPDIR:-/tmp}/network-renderer-nixos-required-substrate.XXXXXX")"
trap 'rm -rf "${tmp_dir}"' EXIT

positive_expr="${tmp_dir}/explicit-wan-group-map.nix"
cat >"${positive_expr}" <<EOF
let
  f = builtins.getFlake "path:${repo_root}";
  lib = f.inputs.nixpkgs.lib;
  assignment = import ${repo_root}/s88/EquipmentModule/mapping/wan-attachment/assignment.nix {
    inherit lib;
    hostName = "lab-host";
    deploymentHostName = "lab-host";
    deploymentHost = {
      wanGroupToUplink = {
        "enterprise::site::wan-a" = "uplink-a";
        "enterprise::site::wan-b" = "uplink-b";
      };
    };
    renderHostConfig = { };
    lookup = {
      hostHasUplinks = true;
      uplinksRaw = {
        uplink-a = { bridge = "br-wan-a"; };
        uplink-b = { bridge = "br-wan-b"; };
      };
      uplinkNames = [ "uplink-a" "uplink-b" ];
      wanGroupNames = [ "enterprise::site::wan-a" "enterprise::site::wan-b" ];
    };
  };
in
builtins.seq assignment.validateStrictWanRendering (builtins.toJSON assignment.wanGroupToUplinkName)
EOF

nix eval \
  --extra-experimental-features 'nix-command flakes' \
  --impure \
  --raw \
  --expr "import ${positive_expr}" \
  >"${tmp_dir}/positive.out"

grep -F '"enterprise::site::wan-a":"uplink-a"' "${tmp_dir}/positive.out" >/dev/null \
  || fail "explicit WAN group map did not preserve wan-a assignment"
grep -F '"enterprise::site::wan-b":"uplink-b"' "${tmp_dir}/positive.out" >/dev/null \
  || fail "explicit WAN group map did not preserve wan-b assignment"

negative_expr="${tmp_dir}/missing-wan-group-map.nix"
cat >"${negative_expr}" <<EOF
let
  f = builtins.getFlake "path:${repo_root}";
  lib = f.inputs.nixpkgs.lib;
  assignment = import ${repo_root}/s88/EquipmentModule/mapping/wan-attachment/assignment.nix {
    inherit lib;
    hostName = "lab-host";
    deploymentHostName = "lab-host";
    deploymentHost = { };
    renderHostConfig = { };
    lookup = {
      hostHasUplinks = true;
      uplinksRaw = {
        uplink-a = { bridge = "br-wan-a"; };
        uplink-b = { bridge = "br-wan-b"; };
      };
      uplinkNames = [ "uplink-a" "uplink-b" ];
      wanGroupNames = [ "enterprise::site::wan-a" "enterprise::site::wan-b" ];
    };
  };
in
builtins.seq assignment.validateStrictWanRendering "unexpected-success"
EOF

set +e
nix eval \
  --extra-experimental-features 'nix-command flakes' \
  --impure \
  --raw \
  --expr "import ${negative_expr}" \
  >"${tmp_dir}/negative.out" \
  2>"${tmp_dir}/negative.err"
rc=$?
set -e

[[ "${rc}" -ne 0 ]] || fail "missing WAN group map was accepted"
grep -F "strict rendering requires explicit WAN uplink assignment for host 'lab-host'" "${tmp_dir}/negative.err" >/dev/null \
  || fail "missing strict substrate refusal diagnostic"
grep -F '"enterprise::site::wan-a"' "${tmp_dir}/negative.err" >/dev/null \
  || fail "missing wan-a in refusal diagnostic"
grep -F '"enterprise::site::wan-b"' "${tmp_dir}/negative.err" >/dev/null \
  || fail "missing wan-b in refusal diagnostic"

pass "nixos-target-required-substrate-refusal"
