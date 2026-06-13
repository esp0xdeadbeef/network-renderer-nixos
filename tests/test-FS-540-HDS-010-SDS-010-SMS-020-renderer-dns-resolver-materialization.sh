#!/usr/bin/env bash
# GAMP-ID: FS-540-HDS-010-SDS-010-SMS-020
# GAMP-SCOPE: software-module-test
# Focused construction test: NixOS renderer DNS resolver materialization.
#
# SMS-020: The NixOS renderer shall consume CPM dns.* fields for interface-level
# resolver configuration and materialize correct unbound config. This test
# verifies the renderer correctly materializes unbound configuration from CPM
# DNS service data, covering resolver addresses, forwarders, listen interfaces,
# access control, namespace fallback, and failure conditions.
#
# Acceptance predicates (AP):
#   AP-1: DNS service data produces unbound with correct listen addresses
#   AP-2: DNS service data produces unbound with correct forward-addr (non-self-ref)
#   AP-3: DNS service data produces correct access-control CIDRs
#   AP-4: DNS service data produces correct local zones and records
#   AP-5: DNS service data produces correct outgoing interfaces from roles
#   AP-6: Missing DNS service data produces null (no unbound config)
#   AP-7: Self-referential forwarder produces diagnostic rejection
#   AP-8: Invalid namespace conflict decision produces diagnostic rejection
#   AP-9: Empty listen/forwarders produces valid minimal unbound config
#   AP-10: Mixed IPv4/IPv6 forwarders detected via hasMixedForwarders
#
# Seeded negatives:
#   N1: Self-referential forwarder (forwarder == listen address) -> REJECT
#   N2: Namespace conflict decision missing requesterScope/namespace -> REJECT
#   N3: Null/missing dnsService -> returns null
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

failures=0

fail() {
  echo "FAIL $*" >&2
  failures=$((failures + 1))
}

pass() {
  echo "  ✓ $*"
}

run_nix_expr() {
  local label="$1"
  local expr="$2"
  local stderr_file="$3"

  if env REPO_ROOT="${repo_root}" nix eval \
    --extra-experimental-features 'nix-command flakes' \
    --impure \
    --expr "${expr}" \
    >"${tmp}/stdout" \
    2>"${stderr_file}"; then
    return 0
  else
    return 1
  fi
}

echo "=== SMT: FS-540-HDS-010-SDS-010-SMS-020 renderer DNS resolver materialization ==="
echo ""

# ─────────────────────────────────────────────────────────────────────
# Common: import facts module
# ─────────────────────────────────────────────────────────────────────
facts_import='
  let
    repoRoot = builtins.getEnv "REPO_ROOT";
    flake = builtins.getFlake ("path:" + repoRoot);
    lib = flake.inputs.nixpkgs.lib;
    pkgs = import flake.inputs.nixpkgs { system = builtins.currentSystem; };
    importFacts = dnsService: interfaces:
      let
        renderedModel = {
          runtimeTarget.services.dns =
            if dnsService == null then {} else dnsService;
          interfaces = if builtins.isAttrs interfaces then interfaces else {};
        };
      in
        import (repoRoot + "/s88/ControlModule/render/containers/dns-services/facts.nix") {
          inherit lib renderedModel;
          forwardingIntent = {};
        };
  in'

# ─────────────────────────────────────────────────────────────────────
# Test 1 (AP-1, AP-2, AP-3): DNS service data -> correct unbound config
# ─────────────────────────────────────────────────────────────────────
echo "Test 1: DNS service -> unbound config (AP-1, AP-2, AP-3)"

stderr1="${tmp}/test1.err"

if run_nix_expr "dns-unbound-config" '
  let
    repoRoot = builtins.getEnv "REPO_ROOT";
    flake = builtins.getFlake ("path:" + repoRoot);
    lib = flake.inputs.nixpkgs.lib;
    pkgs = import flake.inputs.nixpkgs { system = builtins.currentSystem; };
    renderedModel = {
      runtimeTarget.services.dns = {
        listen = [ "10.20.0.1" "fd42:dead:beef:10::1" ];
        forwarders = [ "1.1.1.1" "9.9.9.9" "2606:4700:4700::1111" ];
        allowFrom = [ "10.20.0.0/24" "fd42:dead:beef:10::/64" ];
      };
      interfaces = {};
    };
    facts = import (repoRoot + "/s88/ControlModule/render/containers/dns-services/facts.nix") {
      inherit lib renderedModel;
      forwardingIntent = {};
    };
    hasLoopback = builtins.elem "127.0.0.1" facts.listenAddresses
      && builtins.elem "::1" facts.listenAddresses;
    hasV4Listen = builtins.elem "10.20.0.1" facts.listenAddresses;
    hasV6Listen = builtins.elem "fd42:dead:beef:10::1" facts.listenAddresses;
    listenCountOk = builtins.length facts.listenAddresses == 4;
    hasV4Fwd = builtins.elem "1.1.1.1" facts.forwarders
      && builtins.elem "9.9.9.9" facts.forwarders;
    hasV6Fwd = builtins.elem "2606:4700:4700::1111" facts.forwarders;
    fwdCountOk = builtins.length facts.forwarders == 3;
    hasLoopbackAllow = builtins.elem "127.0.0.0/8" facts.allowFrom
      && builtins.elem "::1/128" facts.allowFrom;
    hasV4Allow = builtins.elem "10.20.0.0/24" facts.allowFrom;
    hasV6Allow = builtins.elem "fd42:dead:beef:10::/64" facts.allowFrom;
    hasMixedFwd = facts.hasMixedForwarders or false;
    notNull = facts != null;
    ok = hasLoopback && hasV4Listen && hasV6Listen && listenCountOk
      && hasV4Fwd && hasV6Fwd && fwdCountOk
      && hasLoopbackAllow && hasV4Allow && hasV6Allow
      && hasMixedFwd && notNull;
    failed = builtins.filter (x: !x.value) [
      { name = "hasLoopback"; value = hasLoopback; }
      { name = "hasV4Listen"; value = hasV4Listen; }
      { name = "hasV6Listen"; value = hasV6Listen; }
      { name = "listenCountOk"; value = listenCountOk; }
      { name = "hasV4Fwd"; value = hasV4Fwd; }
      { name = "hasV6Fwd"; value = hasV6Fwd; }
      { name = "fwdCountOk"; value = fwdCountOk; }
      { name = "hasLoopbackAllow"; value = hasLoopbackAllow; }
      { name = "hasV4Allow"; value = hasV4Allow; }
      { name = "hasV6Allow"; value = hasV6Allow; }
      { name = "hasMixedFwd"; value = hasMixedFwd; }
      { name = "notNull"; value = notNull; }
    ];
  in
    if ok then true
    else throw "unbound config check failed: ${builtins.toJSON (map (x: x.name) failed)}"
' "${stderr1}"; then
  pass "Test 1: DNS service -> unbound config correct"
else
  fail "Test 1: DNS service -> unbound config - stderr follows"
  cat "${stderr1}" >&2
fi

# ─────────────────────────────────────────────────────────────────────
# Test 2 (AP-4): Local zones and records
# ─────────────────────────────────────────────────────────────────────
echo ""
echo "Test 2: Local zones and records (AP-4)"

stderr2="${tmp}/test2.err"

if run_nix_expr "dns-local-zones" '
  let
    repoRoot = builtins.getEnv "REPO_ROOT";
    flake = builtins.getFlake ("path:" + repoRoot);
    lib = flake.inputs.nixpkgs.lib;
    pkgs = import flake.inputs.nixpkgs { system = builtins.currentSystem; };
    renderedModel = {
      runtimeTarget.services.dns = {
        listen = [ "10.20.0.1" ];
        forwarders = [ "1.1.1.1" ];
        allowFrom = [ "10.20.0.0/24" ];
        localZones = [
          { name = "example.local"; type = "static"; }
          { name = "test.internal"; type = "transparent"; }
        ];
        localRecords = [
          { name = "host1.example.local"; a = [ "10.20.0.10" ]; aaaa = [ "fd42::10" ]; }
        ];
      };
      interfaces = {};
    };
    facts = import (repoRoot + "/s88/ControlModule/render/containers/dns-services/facts.nix") {
      inherit lib renderedModel;
      forwardingIntent = {};
    };
    localZones = facts.localZones or [];
    localRecords = facts.localRecords or [];
    hasZone1 = builtins.any (z: z.name == "example.local") localZones;
    hasZone2 = builtins.any (z: z.name == "test.internal") localZones;
    zoneCountOk = builtins.length localZones == 2;
    hasRecord = builtins.any (r: r.name == "host1.example.local") localRecords;
    recordCountOk = builtins.length localRecords == 1;
    ok = hasZone1 && hasZone2 && zoneCountOk && hasRecord && recordCountOk;
  in
    if ok then true
    else throw "local zones/records check failed"
' "${stderr2}"; then
  pass "Test 2: Local zones and records correct"
else
  fail "Test 2: Local zones and records - stderr follows"
  cat "${stderr2}" >&2
fi

# ─────────────────────────────────────────────────────────────────────
# Test 3 (AP-5): Outgoing interfaces from dns roles
# ─────────────────────────────────────────────────────────────────────
echo ""
echo "Test 3: Outgoing interfaces from DNS roles (AP-5)"

stderr3="${tmp}/test3.err"

if run_nix_expr "dns-roles-outgoing" '
  let
    repoRoot = builtins.getEnv "REPO_ROOT";
    flake = builtins.getFlake ("path:" + repoRoot);
    lib = flake.inputs.nixpkgs.lib;
    pkgs = import flake.inputs.nixpkgs { system = builtins.currentSystem; };
    renderedModel = {
      runtimeTarget.services.dns = {
        listen = [ "10.20.0.1" ];
        forwarders = [ "1.1.1.1" ];
        allowFrom = [ "10.20.0.0/24" ];
        roles = {
          recursion = {
            outgoingInterfaces = [ "eth-wan" "eth-overlay" ];
          };
        };
      };
      interfaces = {};
    };
    facts = import (repoRoot + "/s88/ControlModule/render/containers/dns-services/facts.nix") {
      inherit lib renderedModel;
      forwardingIntent = {};
    };
    outgoing = facts.outgoingInterfaces or [];
    hasWan = builtins.elem "eth-wan" outgoing;
    hasOverlay = builtins.elem "eth-overlay" outgoing;
    countOk = builtins.length outgoing == 2;
    ok = hasWan && hasOverlay && countOk;
  in
    if ok then true
    else throw "outgoing interfaces check failed"
' "${stderr3}"; then
  pass "Test 3: Outgoing interfaces from DNS roles correct"
else
  fail "Test 3: Outgoing interfaces - stderr follows"
  cat "${stderr3}" >&2
fi

# ─────────────────────────────────────────────────────────────────────
# Test 4 (AP-6, N3): Null/missing dnsService -> returns null
# ─────────────────────────────────────────────────────────────────────
echo ""
echo "Test 4: Null/missing dnsService -> returns null (AP-6, N3)"

stderr4="${tmp}/test4.err"

if run_nix_expr "dns-null-service" '
  let
    repoRoot = builtins.getEnv "REPO_ROOT";
    flake = builtins.getFlake ("path:" + repoRoot);
    lib = flake.inputs.nixpkgs.lib;
    pkgs = import flake.inputs.nixpkgs { system = builtins.currentSystem; };
    renderedModel = {
      runtimeTarget = {};
      interfaces = {};
    };
    facts = import (repoRoot + "/s88/ControlModule/render/containers/dns-services/facts.nix") {
      inherit lib renderedModel;
      forwardingIntent = {};
    };
  in
    if facts == null then true
    else throw "expected null facts when no dns service"
' "${stderr4}"; then
  pass "Test 4: Null dnsService returns null facts"
else
  fail "Test 4: Null dnsService - stderr follows"
  cat "${stderr4}" >&2
fi

# ─────────────────────────────────────────────────────────────────────
# Test 5 (N1): Self-referential forwarder -> REJECT
# ─────────────────────────────────────────────────────────────────────
echo ""
echo "Test 5: Self-referential forwarder rejection (N1)"

stderr5="${tmp}/test5.err"

if run_nix_expr "dns-self-ref-reject" '
  let
    repoRoot = builtins.getEnv "REPO_ROOT";
    flake = builtins.getFlake ("path:" + repoRoot);
    lib = flake.inputs.nixpkgs.lib;
    pkgs = import flake.inputs.nixpkgs { system = builtins.currentSystem; };
    renderedModel = {
      runtimeTarget.services.dns = {
        listen = [ "10.20.0.1" ];
        forwarders = [ "10.20.0.1" ];
        allowFrom = [ "10.20.0.0/24" ];
      };
      interfaces = {};
    };
    facts = import (repoRoot + "/s88/ControlModule/render/containers/dns-services/facts.nix") {
      inherit lib renderedModel;
      forwardingIntent = {};
    };
  in
    builtins.deepSeq facts false
' "${stderr5}"; then
  fail "Test 5: Self-referential forwarder should have been rejected"
else
  exit_code=$?
  if grep -qF "self-referential forwarder" "${stderr5}"; then
    pass "Test 5: Self-referential forwarder correctly rejected"
  else
    fail "Test 5: Rejected but diagnostic message missing or wrong"
    echo "=== stderr ===" >&2
    cat "${stderr5}" >&2
  fi
fi

# ─────────────────────────────────────────────────────────────────────
# Test 6 (N2): Invalid namespace conflict decision -> REJECT
# ─────────────────────────────────────────────────────────────────────
echo ""
echo "Test 6: Invalid namespace conflict decision rejection (N2)"

stderr6="${tmp}/test6.err"

if run_nix_expr "dns-namespace-conflict-reject" '
  let
    repoRoot = builtins.getEnv "REPO_ROOT";
    flake = builtins.getFlake ("path:" + repoRoot);
    lib = flake.inputs.nixpkgs.lib;
    pkgs = import flake.inputs.nixpkgs { system = builtins.currentSystem; };
    renderedModel = {
      runtimeTarget.services.dns = {
        listen = [ "10.20.0.1" ];
        forwarders = [ "1.1.1.1" ];
        allowFrom = [ "10.20.0.0/24" ];
        namespaceFallback = {
          defaultPublicRecursionFallback = false;
          decisions = [
            { action = "block"; }
          ];
        };
      };
      interfaces = {};
    };
    facts = import (repoRoot + "/s88/ControlModule/render/containers/dns-services/facts.nix") {
      inherit lib renderedModel;
      forwardingIntent = {};
    };
  in
    builtins.deepSeq facts false
' "${stderr6}"; then
  fail "Test 6: Invalid namespace conflict decision should have been rejected"
else
  exit_code=$?
  if grep -qF "requires requesterScope and namespace" "${stderr6}"; then
    pass "Test 6: Invalid namespace conflict decision correctly rejected"
  else
    fail "Test 6: Rejected but diagnostic message missing or wrong"
    echo "=== stderr ===" >&2
    cat "${stderr6}" >&2
  fi
fi

# ─────────────────────────────────────────────────────────────────────
# Test 7 (AP-9): Empty listen/forwarders -> valid minimal config
# ─────────────────────────────────────────────────────────────────────
echo ""
echo "Test 7: Empty listen/forwarders -> valid minimal config (AP-9)"

stderr7="${tmp}/test7.err"

if run_nix_expr "dns-minimal-config" '
  let
    repoRoot = builtins.getEnv "REPO_ROOT";
    flake = builtins.getFlake ("path:" + repoRoot);
    lib = flake.inputs.nixpkgs.lib;
    pkgs = import flake.inputs.nixpkgs { system = builtins.currentSystem; };
    renderedModel = {
      runtimeTarget.services.dns = {
        listen = [];
        forwarders = [];
        allowFrom = [];
      };
      interfaces = {};
    };
    facts = import (repoRoot + "/s88/ControlModule/render/containers/dns-services/facts.nix") {
      inherit lib renderedModel;
      forwardingIntent = {};
    };
    hasLoopback = builtins.elem "127.0.0.1" facts.listenAddresses;
    hasLoopback6 = builtins.elem "::1" facts.listenAddresses;
    hasLoopbackAllow = builtins.elem "127.0.0.0/8" facts.allowFrom;
    fwdEmpty = facts.forwarders == [];
    notNull = facts != null;
    notMixed = !(facts.hasMixedForwarders or false);
    ok = hasLoopback && hasLoopback6 && hasLoopbackAllow && fwdEmpty && notNull && notMixed;
  in
    if ok then true
    else throw "minimal config check failed"
' "${stderr7}"; then
  pass "Test 7: Empty listen/forwarders -> valid minimal config"
else
  fail "Test 7: Minimal config - stderr follows"
  cat "${stderr7}" >&2
fi

# ─────────────────────────────────────────────────────────────────────
# Test 8: IPv4-only forwarders -> hasMixedForwarders = false
# ─────────────────────────────────────────────────────────────────────
echo ""
echo "Test 8: IPv4-only forwarders -> hasMixedForwarders = false"

stderr8="${tmp}/test8.err"

if run_nix_expr "dns-ipv4-only" '
  let
    repoRoot = builtins.getEnv "REPO_ROOT";
    flake = builtins.getFlake ("path:" + repoRoot);
    lib = flake.inputs.nixpkgs.lib;
    pkgs = import flake.inputs.nixpkgs { system = builtins.currentSystem; };
    renderedModel = {
      runtimeTarget.services.dns = {
        listen = [ "10.20.0.1" ];
        forwarders = [ "1.1.1.1" "8.8.8.8" ];
        allowFrom = [ "10.20.0.0/24" ];
      };
      interfaces = {};
    };
    facts = import (repoRoot + "/s88/ControlModule/render/containers/dns-services/facts.nix") {
      inherit lib renderedModel;
      forwardingIntent = {};
    };
    mixed = facts.hasMixedForwarders or true;
    v4Count = builtins.length (facts.forwarder4 or []);
    v6Count = builtins.length (facts.forwarder6 or []);
    ok = !mixed && v4Count == 2 && v6Count == 0;
  in
    if ok then true
    else throw "IPv4-only check failed: mixed=${toString mixed} v4=${toString v4Count} v6=${toString v6Count}"
' "${stderr8}"; then
  pass "Test 8: IPv4-only forwarders correctly classified"
else
  fail "Test 8: IPv4-only forwarders - stderr follows"
  cat "${stderr8}" >&2
fi

# ─────────────────────────────────────────────────────────────────────
# Test 9: upstreams alias works same as forwarders
# ─────────────────────────────────────────────────────────────────────
echo ""
echo "Test 9: upstreams alias -> same as forwarders"

stderr9="${tmp}/test9.err"

if run_nix_expr "dns-upstreams-alias" '
  let
    repoRoot = builtins.getEnv "REPO_ROOT";
    flake = builtins.getFlake ("path:" + repoRoot);
    lib = flake.inputs.nixpkgs.lib;
    pkgs = import flake.inputs.nixpkgs { system = builtins.currentSystem; };
    renderedModel = {
      runtimeTarget.services.dns = {
        listen = [ "10.20.0.1" ];
        upstreams = [ "1.1.1.1" ];
        allowFrom = [ "10.20.0.0/24" ];
      };
      interfaces = {};
    };
    facts = import (repoRoot + "/s88/ControlModule/render/containers/dns-services/facts.nix") {
      inherit lib renderedModel;
      forwardingIntent = {};
    };
    hasFwd = builtins.elem "1.1.1.1" facts.forwarders;
    ok = hasFwd;
  in
    if ok then true
    else throw "upstreams alias check failed"
' "${stderr9}"; then
  pass "Test 9: upstreams alias produces correct forwarders"
else
  fail "Test 9: upstreams alias - stderr follows"
  cat "${stderr9}" >&2
fi

# ─────────────────────────────────────────────────────────────────────
# Test 10: Valid namespace conflict decisions
# ─────────────────────────────────────────────────────────────────────
echo ""
echo "Test 10: Valid namespace conflict decisions"

stderr10="${tmp}/test10.err"

if run_nix_expr "dns-valid-namespace" '
  let
    repoRoot = builtins.getEnv "REPO_ROOT";
    flake = builtins.getFlake ("path:" + repoRoot);
    lib = flake.inputs.nixpkgs.lib;
    pkgs = import flake.inputs.nixpkgs { system = builtins.currentSystem; };
    renderedModel = {
      runtimeTarget.services.dns = {
        listen = [ "10.20.0.1" ];
        forwarders = [ "1.1.1.1" ];
        allowFrom = [ "10.20.0.0/24" ];
        namespaceFallback = {
          defaultPublicRecursionFallback = false;
          decisions = [
            { requesterScope = "tenant-a"; namespace = "example.local"; action = "block"; }
            { requesterScope = "tenant-b"; namespace = "test.local"; action = "deny"; }
            { requesterScope = "guest"; namespace = "public"; action = "allow"; publicRecursionFallback = true; }
          ];
        };
      };
      interfaces = {};
    };
    facts = import (repoRoot + "/s88/ControlModule/render/containers/dns-services/facts.nix") {
      inherit lib renderedModel;
      forwardingIntent = {};
    };
    decisions = facts.namespaceFallbackDecisions or [];
    hasBlock = builtins.any (d: d.action == "block" && d.requesterScope == "tenant-a") decisions;
    hasDeny = builtins.any (d: d.action == "deny" && d.requesterScope == "tenant-b") decisions;
    noAllow = !(builtins.any (d: d.action == "allow") decisions);
    countOk = builtins.length decisions == 2;
    ok = hasBlock && hasDeny && noAllow && countOk;
  in
    if ok then true
    else throw "namespace decisions check failed"
' "${stderr10}"; then
  pass "Test 10: Valid namespace conflict decisions correct"
else
  fail "Test 10: Namespace conflict decisions - stderr follows"
  cat "${stderr10}" >&2
fi

# ─────────────────────────────────────────────────────────────────────
# Summary
# ─────────────────────────────────────────────────────────────────────
echo ""
echo "──────────────────────────────────────────"
if (( failures == 0 )); then
  echo "PASS FS-540-HDS-010-SDS-010-SMS-020 renderer DNS resolver materialization (all 10 tests)"
  exit 0
else
  echo "FAIL FS-540-HDS-010-SDS-010-SMS-020: ${failures} test(s) failed"
  exit 1
fi
