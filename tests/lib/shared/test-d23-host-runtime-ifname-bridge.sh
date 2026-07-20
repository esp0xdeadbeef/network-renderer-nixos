#!/usr/bin/env bash
set -euo pipefail

repo_root="${SMS_TEST_REPO_ROOT:-$(git -C "$(dirname "${BASH_SOURCE[0]}")" rev-parse --show-toplevel)}"

# shellcheck source=tests/lib/test-common.sh
. "${repo_root}/tests/lib/test-common.sh"

result_json="$(mktemp)"
stderr_file="$(mktemp)"
trap 'rm -f "$result_json" "$stderr_file"' EXIT

# ---------------------------------------------------------------------------
# FS-320-HDS-010-SDS-010-SMS-020: rendered interface name contract
#
# The renderer must map logical interface names to rendered names.
# Per FS-930-HDS-010-SDS-010-SMS-040, duplicate rendered interface names
# shall trigger hard diagnostic rejection instead of auto-uniquification.
# Non-duplicate mappings proceed directly without uniquification.
# ---------------------------------------------------------------------------

nix_eval_json_or_fail "FS-320-HDS-010-SDS-010-SMS-020-rendered-name-uniquification" "$result_json" "$stderr_file" \
  env REPO_ROOT="${repo_root}" \
  nix eval --json --extra-experimental-features 'nix-command flakes' --impure \
  --expr '
let
  repoRoot = builtins.getEnv "REPO_ROOT";
  flake = builtins.getFlake ("path:" + repoRoot);
  lib = flake.inputs.nixpkgs.lib;

  renderedNames = import (repoRoot + "/s88/Unit/mapping/runtime-targets/interfaces/rendered-names.nix") {
    inherit lib;
    runtimeContext = {
      emittedInterfacesForUnit = { cpm, unitName, file }:
        cpm.interfaces or {};
    };
    common = {
      sortedAttrNames = attrs: builtins.attrNames attrs;
    };
  };

  inherit (renderedNames) renderedInterfaceNamesForUnit;

  check = label: pred:
    if pred then { inherit label; ok = true; }
    else { inherit label; ok = false; detail = "assertion failed"; };

  # Helper: call renderedInterfaceNamesForUnit wrapped in tryEval
  tryCall = cpm: unitName: file:
    builtins.tryEval (renderedInterfaceNamesForUnit {
      inherit cpm unitName file;
    });

  checks = [

    # ================================================================
    # T1: No duplicates — each ifName gets its desired name
    #     (non-duplicate: no rejection, direct mapping)
    # ================================================================
    (check "T1a-no-duplicates" (
      let
        evaled = tryCall {
          interfaces = {
            "commercial-vpn" = { renderedIfName = "ens80"; };
            "ens20"          = { renderedIfName = "ens20"; };
            "p2p-link"      = { renderedIfName = "ens21"; };
          };
        } "test-unit" "test-fs320-hds010-sds010-sms020";
      in evaled.success
         && evaled.value."commercial-vpn" == "ens80"
         && evaled.value.ens20 == "ens20"
         && evaled.value."p2p-link" == "ens21"
    ))

    # ================================================================
    # T2: Duplicate desired names — diagnostic rejection
    #     Per FS-930 SMS-040: duplicates must throw, not uniquify
    # ================================================================
    (check "T2a-duplicates-rejected" (
      let
        evaled = tryCall {
          interfaces = {
            "ens20" = { renderedIfName = "ens20"; };
            "p2p-nixos-core-commercial-vpn-nixos-upstream-selector" = { renderedIfName = "ens20"; };
          };
        } "esp0xdeadbeef::site-a::esp0xdeadbeef-site-a-nixos-core-commercial-vpn"
          "test-fs320-hds010-sds010-sms020";
      in ! evaled.success
    ))

    # ================================================================
    # T3: Bug reproduction — three interfaces, two want "ens20"
    #     Must be rejected per FS-930 SMS-040
    # ================================================================
    (check "T3a-bug-reproduction-rejected" (
      let
        evaled = tryCall {
          interfaces = {
            "commercial-vpn" = { renderedIfName = "ens80"; };
            "ens20" = { renderedIfName = "ens20"; };
            "p2p-nixos-core-commercial-vpn-nixos-upstream-selector" = { renderedIfName = "ens20"; };
          };
        } "esp0xdeadbeef::site-a::esp0xdeadbeef-site-a-nixos-core-commercial-vpn"
          "test-fs320-hds010-sds010-sms020";
      in ! evaled.success
    ))

    # ================================================================
    # T4: Three duplicates — diagnostic rejection
    # ================================================================
    (check "T4a-three-duplicates-rejected" (
      let
        evaled = tryCall {
          interfaces = {
            "a" = { renderedIfName = "ens20"; };
            "b" = { renderedIfName = "ens20"; };
            "c" = { renderedIfName = "ens20"; };
          };
        } "test-unit" "test-fs320-hds010-sds010-sms020";
      in ! evaled.success
    ))

    # ================================================================
    # T5: Deterministic rejection — same duplicate input reliably throws
    # ================================================================
    (check "T5a-deterministic-rejection" (
      let
        mkResult = tryCall {
          interfaces = {
            "ens20" = { renderedIfName = "ens20"; };
            "p2p"   = { renderedIfName = "ens20"; };
          };
        } "test-unit" "test-fs320-hds010-sds010-sms020";
        r1 = mkResult.success;
        r2 = mkResult.success;
      in r1 == false && r2 == false
    ))

    # ================================================================
    # T6: Interfaces without renderedIfName fall back to ifName
    #     (no regression on fallback behavior)
    # ================================================================
    (check "T6a-fallback-to-ifName" (
      let
        evaled = tryCall {
          interfaces = { "my-interface" = { }; };
        } "test-unit" "test-fs320-hds010-sds010-sms020";
      in evaled.success && evaled.value."my-interface" == "my-interface"
    ))

    # ================================================================
    # T7: Single interface with explicit renderedIfName
    # ================================================================
    (check "T7a-single-interface-ok" (
      let
        evaled = tryCall {
          interfaces = { "ens20" = { renderedIfName = "ens20"; }; };
        } "test-unit" "test-fs320-hds010-sds010-sms020";
      in evaled.success && evaled.value ? ens20 && evaled.value.ens20 == "ens20"
    ))

  ];

  okCount = builtins.length (builtins.filter (c: c.ok) checks);
  failed = builtins.filter (c: !c.ok) checks;
in
{
  ok = failed == [];
  okCount = okCount;
  total = builtins.length checks;
  failed = map (c: c.label) failed;
}
'

assert_json_checks_ok "FS-320-HDS-010-SDS-010-SMS-020" "$result_json"

echo "PASS FS-320-HDS-010-SDS-010-SMS-020: all assertions passed"
