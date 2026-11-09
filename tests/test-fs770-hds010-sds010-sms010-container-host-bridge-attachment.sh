#!/usr/bin/env bash
set -euo pipefail
# GAMP-ID: FS-770-HDS-010-SDS-010-SMS-010
# GAMP-SCOPE: software-module-test
#
# FS-770-HDS-010: a container-hosted runtime target attaches every container
# interface to the host bridge the platform binding names for it, and fails
# closed when that bridge is not rendered on the host.
#
#   P1  every container (not just the first) receives hostBridge/extraVeths
#   P2  without a binding the renderer invents nothing
#   N1  a binding that names an unrendered bridge fails closed
#
# Renderer SMT construction evidence for the realization boundary only; no
# SIT/HAT/SAT runtime acceptance is claimed.

repo_root="${SMS_TEST_REPO_ROOT:-$(git rev-parse --show-toplevel)}"
source "${repo_root}/tests/lib/test-common.sh"

module_path="${repo_root}/s88/ControlModule/render/container-bridges.nix"

common="
let
  lib = (import <nixpkgs> { }).lib;
  module = import \"${module_path}\";
  netdevs = {
    br-wan = { netdevConfig = { Kind = \"bridge\"; Name = \"br-wan\"; }; };
    br-lan-trunk = { netdevConfig = { Kind = \"bridge\"; Name = \"br-lan-trunk\"; }; };
  };
  rendered = {
    core = { autoStart = true; };
    policy = { autoStart = true; };
    access-clients = { autoStart = true; };
    tang = { autoStart = true; };
  };
  bindingAll = {
    categories.deployment.containerTargets.s-nodus.containers = {
      core = { hostBridge = \"br-lan-trunk\"; interfaces = { wan = { bridge = \"br-wan\"; }; }; };
      policy = { hostBridge = \"br-lan-trunk\"; };
      access-clients = { interfaces = { wan = { bridge = \"br-wan\"; }; ens3 = { bridge = \"br-lan-trunk\"; }; }; };
      tang = { hostBridge = \"br-lan-trunk\"; };
    };
  };
in
"

nix_eval_true_or_fail "FS-770-HDS-010-SDS-010-SMS-010 P1 every container gets its host bridge" \
  env REPO_ROOT="${repo_root}" \
    nix eval --extra-experimental-features 'nix-command flakes' --impure --expr "${common}"'
    let
      r = module { inherit lib; hostName = "s-nodus"; renderedNetdevs = netdevs; platformBinding = bindingAll; };
      out = r.applyAll rendered;
      names = builtins.attrNames rendered;
    in
    builtins.all (n: (out.${n}.hostBridge or null) == "br-lan-trunk"
                     || (out.${n}.extraVeths.wan.hostBridge or null) == "br-wan") names
    && (out.access-clients.extraVeths.ens3.hostBridge or null) == "br-lan-trunk"
    && (out.core.extraVeths.wan.hostBridge or null) == "br-wan"
    && r.diagnostics rendered == [ ]
'

nix_eval_true_or_fail "FS-770-HDS-010-SDS-010-SMS-010 P2 no binding invents nothing" \
  env REPO_ROOT="${repo_root}" \
    nix eval --extra-experimental-features 'nix-command flakes' --impure --expr "${common}"'
    let
      r = module { inherit lib; hostName = "s-nodus"; renderedNetdevs = netdevs; platformBinding = null; };
      out = r.applyAll rendered;
    in
    builtins.all (n: !(out.${n} ? hostBridge) && !(out.${n} ? extraVeths)) (builtins.attrNames rendered)
    && r.diagnostics rendered == [ ]
'

set +e
n1_out="$(nix eval --extra-experimental-features 'nix-command flakes' --impure --expr "${common}"'
  let
    bad = { categories.deployment.containerTargets.s-nodus.containers.core =
              { interfaces = { wan = { bridge = "br-does-not-exist"; }; }; }; };
    r = module { inherit lib; hostName = "s-nodus"; renderedNetdevs = netdevs; platformBinding = bad; };
  in r.applyAll rendered' 2>&1)"
n1_rc=$?
set -e
[[ ${n1_rc} -ne 0 ]] || fail "FS-770-HDS-010-SDS-010-SMS-010 N1 expected fail-closed, got success"
grep -q 'CONTAINER_HOST_BRIDGE_MISSING' <<<"${n1_out}" || {
  echo "${n1_out}" >&2
  fail "FS-770-HDS-010-SDS-010-SMS-010 N1 error did not name CONTAINER_HOST_BRIDGE_MISSING"
}
pass "FS-770-HDS-010-SDS-010-SMS-010 N1 unrendered host bridge fails closed"
