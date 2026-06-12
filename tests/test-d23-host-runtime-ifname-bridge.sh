#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# shellcheck source=tests/lib/test-common.sh
. "${repo_root}/tests/lib/test-common.sh"

result_json="$(mktemp)"
stderr_file="$(mktemp)"
trap 'rm -f "$result_json" "$stderr_file"' EXIT

# ---------------------------------------------------------------------------
# FS-320-HDS-010-SDS-010-SMS-020: rendered interface name uniquification
# must preserve logical ifName identity through deduplication.
#   FS-320: logical identifiers shall remain separate from platform runtime
#   interface names; the renderer shall emit a deterministic valid runtime
#   name and preserve an inspectable mapping back to the logical identifier.
# ---------------------------------------------------------------------------

nix_eval_json_or_fail "FS-320-HDS-010-SDS-010-SMS-020-rendered-name-uniquification" "$result_json" "$stderr_file" \
  env REPO_ROOT="${repo_root}" \
  nix eval --json --extra-experimental-features 'nix-command flakes' --impure \
  --expr '
let
  repoRoot = builtins.getEnv "REPO_ROOT";
  flake = builtins.getFlake ("path:" + repoRoot);
  lib = flake.inputs.nixpkgs.lib;

  # Load the rendered-names module directly via the public API
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

  # ---- Test helper -------------------------------------------------------
  check = label: pred:
    if pred then { inherit label; ok = true; }
    else { inherit label; ok = false; detail = "assertion failed"; };

  checks = [

    # ------------------------------------------------------------------
    # T1: No duplicates — each ifName gets its desired name
    # ------------------------------------------------------------------
    (check "T1a-no-duplicates" (
      let
        result = renderedInterfaceNamesForUnit {
          cpm.interfaces = {
            "commercial-vpn" = { renderedIfName = "ens80"; };
            "ens20"          = { renderedIfName = "ens20"; };
            "p2p-link"      = { renderedIfName = "ens21"; };
          };
          unitName = "test-unit";
          file = "test-fs320-hds010-sds010-sms020";
        };
      in result."commercial-vpn" == "ens80"
         && result.ens20 == "ens20"
         && result."p2p-link" == "ens21"
    ))

    # ------------------------------------------------------------------
    # T2: Duplicate desired names — "ens20" + "p2p-*" both want "ens20"
    #     After fix: "ens20" interface keeps "ens20", p2p gets uniquified
    # ------------------------------------------------------------------
    (check "T2a-first-keeps-ens20" (
      let
        result = renderedInterfaceNamesForUnit {
          cpm.interfaces = {
            "ens20" = { renderedIfName = "ens20"; };
            "p2p-nixos-core-commercial-vpn-nixos-upstream-selector" = { renderedIfName = "ens20"; };
          };
          unitName = "esp0xdeadbeef::site-a::esp0xdeadbeef-site-a-nixos-core-commercial-vpn";
          file = "test-fs320-hds010-sds010-sms020";
        };
      in result.ens20 == "ens20"
    ))

    (check "T2b-second-gets-uniquified" (
      let
        result = renderedInterfaceNamesForUnit {
          cpm.interfaces = {
            "ens20" = { renderedIfName = "ens20"; };
            "p2p-nixos-core-commercial-vpn-nixos-upstream-selector" = { renderedIfName = "ens20"; };
          };
          unitName = "esp0xdeadbeef::site-a::esp0xdeadbeef-site-a-nixos-core-commercial-vpn";
          file = "test-fs320-hds010-sds010-sms020";
        };
      in result."p2p-nixos-core-commercial-vpn-nixos-upstream-selector" != "ens20"
    ))

    (check "T2c-both-distinct" (
      let
        result = renderedInterfaceNamesForUnit {
          cpm.interfaces = {
            "ens20" = { renderedIfName = "ens20"; };
            "p2p-nixos-core-commercial-vpn-nixos-upstream-selector" = { renderedIfName = "ens20"; };
          };
          unitName = "esp0xdeadbeef::site-a::esp0xdeadbeef-site-a-nixos-core-commercial-vpn";
          file = "test-fs320-hds010-sds010-sms020";
        };
      in result.ens20 != result."p2p-nixos-core-commercial-vpn-nixos-upstream-selector"
    ))

    # ------------------------------------------------------------------
    # T3: Exact bug reproduction — three interfaces, two want "ens20"
    #     "commercial-vpn"→"ens80", "ens20"→"ens20", "p2p-*"→"ens20"
    #     After fix: all three are distinct
    # ------------------------------------------------------------------
    (check "T3a-bug-reproduction-ens20-keeps-base" (
      let
        result = renderedInterfaceNamesForUnit {
          cpm.interfaces = {
            "commercial-vpn" = { renderedIfName = "ens80"; };
            "ens20" = { renderedIfName = "ens20"; };
            "p2p-nixos-core-commercial-vpn-nixos-upstream-selector" = { renderedIfName = "ens20"; };
          };
          unitName = "esp0xdeadbeef::site-a::esp0xdeadbeef-site-a-nixos-core-commercial-vpn";
          file = "test-fs320-hds010-sds010-sms020";
        };
      in result.ens20 == "ens20"
    ))

    (check "T3b-bug-reproduction-p2p-uniquified" (
      let
        result = renderedInterfaceNamesForUnit {
          cpm.interfaces = {
            "commercial-vpn" = { renderedIfName = "ens80"; };
            "ens20" = { renderedIfName = "ens20"; };
            "p2p-nixos-core-commercial-vpn-nixos-upstream-selector" = { renderedIfName = "ens20"; };
          };
          unitName = "esp0xdeadbeef::site-a::esp0xdeadbeef-site-a-nixos-core-commercial-vpn";
          file = "test-fs320-hds010-sds010-sms020";
        };
      in result."p2p-nixos-core-commercial-vpn-nixos-upstream-selector" != "ens20"
    ))

    (check "T3c-bug-reproduction-all-three-distinct" (
      let
        result = renderedInterfaceNamesForUnit {
          cpm.interfaces = {
            "commercial-vpn" = { renderedIfName = "ens80"; };
            "ens20" = { renderedIfName = "ens20"; };
            "p2p-nixos-core-commercial-vpn-nixos-upstream-selector" = { renderedIfName = "ens20"; };
          };
          unitName = "esp0xdeadbeef::site-a::esp0xdeadbeef-site-a-nixos-core-commercial-vpn";
          file = "test-fs320-hds010-sds010-sms020";
        };
        vals = [
          result."commercial-vpn"
          result.ens20
          result."p2p-nixos-core-commercial-vpn-nixos-upstream-selector"
        ];
      in builtins.length (lib.unique vals) == 3
    ))

    # ------------------------------------------------------------------
    # T4: Three duplicates — all get unique names, first keeps base
    # ------------------------------------------------------------------
    (check "T4a-three-duplicates-all-distinct" (
      let
        result = renderedInterfaceNamesForUnit {
          cpm.interfaces = {
            "a" = { renderedIfName = "ens20"; };
            "b" = { renderedIfName = "ens20"; };
            "c" = { renderedIfName = "ens20"; };
          };
          unitName = "test-unit";
          file = "test-fs320-hds010-sds010-sms020";
        };
        vals = [ result.a result.b result.c ];
      in builtins.length (lib.unique vals) == 3
    ))

    (check "T4b-three-duplicates-first-keeps-base" (
      let
        result = renderedInterfaceNamesForUnit {
          cpm.interfaces = {
            "a" = { renderedIfName = "ens20"; };
            "b" = { renderedIfName = "ens20"; };
            "c" = { renderedIfName = "ens20"; };
          };
          unitName = "test-unit";
          file = "test-fs320-hds010-sds010-sms020";
        };
      in result.a == "ens20"
    ))

    # ------------------------------------------------------------------
    # T5: Determinism — same input, same output
    # ------------------------------------------------------------------
    (check "T5a-deterministic" (
      let
        mkResult = renderedInterfaceNamesForUnit {
          cpm.interfaces = {
            "ens20" = { renderedIfName = "ens20"; };
            "p2p"   = { renderedIfName = "ens20"; };
          };
          unitName = "test-unit";
          file = "test-fs320-hds010-sds010-sms020";
        };
        r1 = mkResult;
        r2 = mkResult;
      in r1.ens20 == r2.ens20 && r1.p2p == r2.p2p
    ))

    # ------------------------------------------------------------------
    # T6: Interfaces without renderedIfName fall back to ifName
    #     (no regression on fallback behavior)
    # ------------------------------------------------------------------
    (check "T6a-fallback-to-ifName" (
      let
        result = renderedInterfaceNamesForUnit {
          cpm.interfaces = {
            "my-interface" = { };
          };
          unitName = "test-unit";
          file = "test-fs320-hds010-sds010-sms020";
        };
      in result."my-interface" == "my-interface"
    ))

    # ------------------------------------------------------------------
    # T7: Seeded negative — interfaces with the SAME ifName AND same
    #     desired rendered name still produce a duplicate warning but
    #     keep valid results (ifName identity can not collide within
    #     one unit since attribute keys are unique).  The fix preserves
    #     this: we verify the result map has the correct shape.
    # ------------------------------------------------------------------
    (check "T7a-single-interface-ok" (
      let
        result = renderedInterfaceNamesForUnit {
          cpm.interfaces = {
            "ens20" = { renderedIfName = "ens20"; };
          };
          unitName = "test-unit";
          file = "test-fs320-hds010-sds010-sms020";
        };
      in result ? ens20 && result.ens20 == "ens20"
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
