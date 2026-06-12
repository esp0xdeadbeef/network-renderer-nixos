#!/usr/bin/env bash
# GAMP-ID: FS-540-HDS-010-SDS-010-SMS-035
# GAMP-SCOPE: software-module-test
# Construction test for renderer DNS nft materialization
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

echo "=== SMT: FS-540-HDS-010-SDS-010-SMS-035 renderer DNS nft materialization ==="
echo ""

# ─────────────────────────────────────────────────────────────────────
# Test 1 (AP-1, AP-3): Policy module produces nft rules with relation
# IDs as comments for both allow and deny DNS relations.
# ─────────────────────────────────────────────────────────────────────
echo "Test 1: DNS communicationContract relations → nft rules with relation ID comments"

stderr1="${tmp}/test1.err"

if run_nix_expr "dns-relation-nft-comments" '
  let
    repoRoot = builtins.getEnv "REPO_ROOT";
    flake = builtins.getFlake ("path:" + repoRoot);
    lib = flake.inputs.nixpkgs.lib;
    pkgs = import flake.inputs.nixpkgs { system = builtins.currentSystem; };

    policy = import (repoRoot + "/s88/ControlModule/firewall/policy/policy.nix") {
      inherit lib;
      communicationContract = {
        relations = [
          {
            id = "allow-tenant-a-dns-to-resolver";
            from = "tenant-a";
            to = "dns-resolver";
            trafficType = "dns";
            action = "allow";
            priority = 100;
          }
          {
            id = "deny-tenant-b-dns-direct";
            from = "tenant-b";
            to = "dns-resolver";
            trafficType = "dns";
            action = "deny";
            priority = 200;
          }
        ];
        trafficTypes = [
          {
            name = "dns";
            match = [
              { proto = "udp"; dports = [ 53 ]; }
              { proto = "tcp"; dports = [ 53 ]; }
            ];
          }
        ];
      };
      endpointMap = {
        resolveEndpoint = scope: [];
        resolveRelationEndpoint = relation: scope:
          if scope == "tenant-a" then [ "if-tenant-a" ]
          else if scope == "tenant-b" then [ "if-tenant-b" ]
          else if scope == "dns-resolver" then [ "if-resolver" ]
          else [];
      };
      forwardingIntent = null;
    };

    forwardRules = policy.forwardRules or [];

    # Check allow rule has the relation ID comment
    hasAllowComment = builtins.any
      (rule: lib.hasInfix "comment \"allow-tenant-a-dns-to-resolver\"" rule)
      forwardRules;

    # Check deny rule has the relation ID comment and uses drop action
    hasDenyComment = builtins.any
      (rule: lib.hasInfix "comment \"deny-tenant-b-dns-direct\"" rule && lib.hasInfix "drop" rule)
      forwardRules;

    # Check allow rule uses accept action
    hasAcceptAction = builtins.any
      (rule: lib.hasInfix "comment \"allow-tenant-a-dns-to-resolver\"" rule && lib.hasInfix "accept" rule)
      forwardRules;

    # Check both UDP and TCP rules are present
    hasUdpRule = builtins.any
      (rule: lib.hasInfix "comment \"allow-tenant-a-dns-to-resolver\"" rule && lib.hasInfix "udp dport { 53 }" rule)
      forwardRules;

    hasTcpRule = builtins.any
      (rule: lib.hasInfix "comment \"allow-tenant-a-dns-to-resolver\"" rule && lib.hasInfix "tcp dport { 53 }" rule)
      forwardRules;

    # DNS interface names should be in the rules
    hasCorrectInterfaces = builtins.any
      (rule: lib.hasInfix "iifname \"if-tenant-a\"" rule && lib.hasInfix "oifname \"if-resolver\"" rule)
      forwardRules;

    ok = hasAllowComment && hasDenyComment && hasAcceptAction && hasUdpRule && hasTcpRule && hasCorrectInterfaces;
    failed = builtins.filter (x: !x) [
      { name = "hasAllowComment"; value = hasAllowComment; }
      { name = "hasDenyComment"; value = hasDenyComment; }
      { name = "hasAcceptAction"; value = hasAcceptAction; }
      { name = "hasUdpRule"; value = hasUdpRule; }
      { name = "hasTcpRule"; value = hasTcpRule; }
      { name = "hasCorrectInterfaces"; value = hasCorrectInterfaces; }
    ];
  in
    if ok then true
    else throw "DNS nft relation comment checks failed: ${builtins.toJSON (map (x: x.name) failed)}"
' "${stderr1}"; then
  pass "Test 1: DNS relation nft rules have correct comments and actions"
else
  fail "Test 1: DNS relation nft rules — stderr follows"
  cat "${stderr1}" >&2
fi

# ─────────────────────────────────────────────────────────────────────
# Test 2 (AP-2): dns-services module produces non-self-referential
# forward-addr when given valid forwarders.
# ─────────────────────────────────────────────────────────────────────
echo ""
echo "Test 2: Non-self-referential forward-addr (AP-2)"

stderr2="${tmp}/test2.err"

if run_nix_expr "dns-non-self-ref-forward" '
  let
    repoRoot = builtins.getEnv "REPO_ROOT";
    flake = builtins.getFlake ("path:" + repoRoot);
    lib = flake.inputs.nixpkgs.lib;
    pkgs = import flake.inputs.nixpkgs { system = builtins.currentSystem; };

    rendered = import (repoRoot + "/s88/ControlModule/render/containers/dns-services.nix") {
      inherit lib pkgs;
      renderedModel = {
        runtimeTarget = {
          services = {
            dns = {
              listen = [ "10.20.0.1" "fd42:dead:beef:10::1" ];
              forwarders = [ "1.1.1.1" "9.9.9.9" "2606:4700:4700::1111" ];
              allowFrom = [ "10.20.0.0/24" ];
            };
          };
        };
      };
      forwardingIntent = {};
    };

    forwardZone = builtins.head (rendered.services.unbound.settings."forward-zone" or []);
    forwardAddrs = forwardZone."forward-addr" or [];

    # Verify forward-addr does NOT contain any listen addresses (non-self-referential)
    listenAddrs = rendered.services.unbound.settings.server.interface or [];
    hasSelfRef = builtins.any (fa: builtins.elem fa listenAddrs) forwardAddrs;

    # Verify expected forwarders are present (excluding loopback)
    hasValidForwarders =
      builtins.elem "1.1.1.1" forwardAddrs
      && builtins.elem "9.9.9.9" forwardAddrs
      && builtins.elem "2606:4700:4700::1111" forwardAddrs;

    # Verify listen addresses are correct
    hasCorrectListen =
      builtins.elem "10.20.0.1" listenAddrs
      && builtins.elem "fd42:dead:beef:10::1" listenAddrs;

    ok = !hasSelfRef && hasValidForwarders && hasCorrectListen;
  in
    if ok then true
    else throw "unbound forward-addr validation failed: selfRef=${toString hasSelfRef} validFwd=${toString hasValidForwarders} listen=${toString hasCorrectListen}"
' "${stderr2}"; then
  pass "Test 2: Non-self-referential forward-addr correct"
else
  fail "Test 2: Non-self-referential forward-addr — stderr follows"
  cat "${stderr2}" >&2
fi

# ─────────────────────────────────────────────────────────────────────
# Test 3 (N1): Self-referential forwarder → rejection with diagnostic
# ─────────────────────────────────────────────────────────────────────
echo ""
echo "Test 3: Self-referential forwarder rejection (N1)"

stderr3="${tmp}/test3.err"

if run_nix_expr "dns-self-ref-forward" '
  let
    repoRoot = builtins.getEnv "REPO_ROOT";
    flake = builtins.getFlake ("path:" + repoRoot);
    lib = flake.inputs.nixpkgs.lib;
    pkgs = import flake.inputs.nixpkgs { system = builtins.currentSystem; };

    rendered = import (repoRoot + "/s88/ControlModule/render/containers/dns-services.nix") {
      inherit lib pkgs;
      renderedModel = {
        runtimeTarget = {
          services = {
            dns = {
              listen = [ "10.20.0.1" ];
              forwarders = [ "10.20.0.1" ];  # Self-referential!
              allowFrom = [ "10.20.0.0/24" ];
            };
          };
        };
      };
      forwardingIntent = {};
    };
  in
    builtins.deepSeq rendered false
' "${stderr3}"; then
  fail "Test 3: Self-referential forwarder should have been rejected"
  echo "ERROR: renderer accepted self-referential forwarder" >&2
else
  exit_code=$?
  # Check stderr contains the expected diagnostic
  if grep -qF "self-referential forwarder" "${stderr3}"; then
    pass "Test 3: Self-referential forwarder correctly rejected"
    echo "  diagnostic: $(grep -o 'rejects self-referential forwarder: .*' "${stderr3}" | head -1)"
  else
    fail "Test 3: Rejected but diagnostic message missing or wrong"
    echo "=== stderr ===" >&2
    cat "${stderr3}" >&2
  fi
fi

# ─────────────────────────────────────────────────────────────────────
# Test 4 (N2): Zero DNS relations → zero nft rules + diagnostic
# ─────────────────────────────────────────────────────────────────────
echo ""
echo "Test 4: Zero DNS relations → zero nft rules (N2)"

stderr4="${tmp}/test4.err"

if run_nix_expr "dns-zero-relations" '
  let
    repoRoot = builtins.getEnv "REPO_ROOT";
    flake = builtins.getFlake ("path:" + repoRoot);
    lib = flake.inputs.nixpkgs.lib;
    pkgs = import flake.inputs.nixpkgs { system = builtins.currentSystem; };

    policy = import (repoRoot + "/s88/ControlModule/firewall/policy/policy.nix") {
      inherit lib;
      communicationContract = {
        relations = [
          {
            id = "allow-http";
            from = "tenant-a";
            to = "web-server";
            trafficType = "http";
            action = "allow";
            priority = 100;
          }
        ];
        trafficTypes = [
          {
            name = "http";
            match = [
              { proto = "tcp"; dports = [ 80 443 ]; }
            ];
          }
          {
            name = "dns";
            match = [
              { proto = "udp"; dports = [ 53 ]; }
              { proto = "tcp"; dports = [ 53 ]; }
            ];
          }
        ];
      };
      endpointMap = {
        resolveEndpoint = scope: [];
        resolveRelationEndpoint = relation: scope:
          if scope == "tenant-a" then [ "if-tenant-a" ]
          else if scope == "web-server" then [ "if-web" ]
          else [];
      };
      forwardingIntent = null;
    };

    forwardRules = policy.forwardRules or [];

    # No relation has trafficType "dns", so no DNS rules should exist
    hasDnsRule = builtins.any
      (rule: lib.hasInfix "udp dport { 53 }" rule || lib.hasInfix "tcp dport { 53 }" rule)
      forwardRules;

    # But non-DNS rules (http) should still be present
    hasHttpRule = builtins.any
      (rule: lib.hasInfix "comment \"allow-http\"" rule)
      forwardRules;

    ok = !hasDnsRule && hasHttpRule;
  in
    if ok then true
    else throw "zero DNS relations check failed: hasDnsRule=${toString hasDnsRule} hasHttpRule=${toString hasHttpRule}"
' "${stderr4}"; then
  pass "Test 4: Zero DNS relations → zero DNS nft rules (non-DNS rules preserved)"
else
  fail "Test 4: Zero DNS relations — stderr follows"
  cat "${stderr4}" >&2
fi

# ─────────────────────────────────────────────────────────────────────
# Test 5 (AP-4): No DNS relations at all → zero DNS rules, module works
# correctly (fail-closed by not emitting DNS rules).
# ─────────────────────────────────────────────────────────────────────
echo ""
echo "Test 5: Empty communicationContract → zero rules"

stderr5="${tmp}/test5.err"

if run_nix_expr "dns-empty-contract" '
  let
    repoRoot = builtins.getEnv "REPO_ROOT";
    flake = builtins.getFlake ("path:" + repoRoot);
    lib = flake.inputs.nixpkgs.lib;
    pkgs = import flake.inputs.nixpkgs { system = builtins.currentSystem; };

    # Empty contract should be rejected by existing validation
    policy = import (repoRoot + "/s88/ControlModule/firewall/policy/policy.nix") {
      inherit lib;
      communicationContract = {};
      endpointMap = {
        resolveEndpoint = scope: [];
        resolveRelationEndpoint = relation: scope: [];
      };
      forwardingIntent = null;
    };
  in
    builtins.deepSeq policy false
' "${stderr5}"; then
  fail "Test 5: Empty communicationContract should have been rejected"
else
  exit_code=$?
  if grep -qF "missing communication contract" "${stderr5}"; then
    pass "Test 5: Empty communicationContract correctly rejected (missing communication contract)"
  else
    fail "Test 5: Rejected but diagnostic message missing or wrong"
    echo "=== stderr ===" >&2
    cat "${stderr5}" >&2
  fi
fi

# ─────────────────────────────────────────────────────────────────────
# Test 6: DNS deny rules are ordered after allows (AP-3 extended)
# Verify deny rules appear after allow rules in the output ordering.
# ─────────────────────────────────────────────────────────────────────
echo ""
echo "Test 6: Deny rules ordered after allows (AP-3 ordering)"

stderr6="${tmp}/test6.err"

if run_nix_expr "dns-deny-ordering" '
let
  repoRoot = builtins.getEnv "REPO_ROOT";
  flake = builtins.getFlake ("path:" + repoRoot);
  lib = flake.inputs.nixpkgs.lib;

  policy = import (repoRoot + "/s88/ControlModule/firewall/policy/policy.nix") {
    inherit lib;
    communicationContract = {
      relations = [
        {
          id = "allow-dns";
          from = "client";
          to = "resolver";
          trafficType = "dns";
          action = "allow";
          priority = 100;
        }
        {
          id = "deny-dns";
          from = "restricted";
          to = "resolver";
          trafficType = "dns";
          action = "deny";
          priority = 200;
        }
      ];
      trafficTypes = [
        {
          name = "dns";
          match = [
            { proto = "udp"; dports = [ 53 ]; }
          ];
        }
      ];
    };
    endpointMap = {
      resolveEndpoint = scope: [];
      resolveRelationEndpoint = relation: scope:
        if scope == "client" then [ "if-client" ]
        else if scope == "restricted" then [ "if-restricted" ]
        else if scope == "resolver" then [ "if-resolver" ]
        else [];
    };
    forwardingIntent = null;
  };

  forwardRules = policy.forwardRules or [];

  # Check that allow rule exists and deny rule exists
  hasAllow = builtins.any
    (rule: lib.hasInfix "comment \"allow-dns\"" rule)
    forwardRules;
  hasDeny = builtins.any
    (rule: lib.hasInfix "comment \"deny-dns\"" rule)
    forwardRules;

  # Verify deny uses "drop" action (not accept)
  denyUsesDrop = builtins.any
    (rule: lib.hasInfix "comment \"deny-dns\"" rule && !(lib.hasInfix "accept" rule))
    forwardRules;

  # Concatenated rules string to check ordering
  allRules = builtins.concatStringsSep "\n" forwardRules;
  allowPos = builtins.match "(.*)comment \"allow-dns\".*" allRules;
  denyPos = builtins.match "(.*)comment \"deny-dns\".*" allRules;

  # Allow must appear before deny in the sorted output
  # Verify by checking that the substring before deny contains the allow comment
  denyPrefix = builtins.head (builtins.match "(.*)comment \"deny-dns\".*" allRules);
  allowBeforeDeny = lib.hasInfix "comment \"allow-dns\"" denyPrefix;

  ok = hasAllow && hasDeny && denyUsesDrop && allowBeforeDeny;
in
  if ok then true
  else throw "deny ordering failed: hasAllow=${toString hasAllow} hasDeny=${toString hasDeny} denyUsesDrop=${toString denyUsesDrop} allowBeforeDeny=${toString allowBeforeDeny}"
' "${stderr6}"; then
  pass "Test 6: Allow rules ordered before deny rules"
else
  fail "Test 6: Deny ordering — stderr follows"
  cat "${stderr6}" >&2
fi

# ─────────────────────────────────────────────────────────────────────
# Summary
# ─────────────────────────────────────────────────────────────────────
echo ""
echo "──────────────────────────────────────────"
if (( failures == 0 )); then
  echo "PASS FS-540-HDS-010-SDS-010-SMS-035 renderer DNS nft materialization (all 6 tests)"
  exit 0
else
  echo "FAIL FS-540-HDS-010-SDS-010-SMS-035: ${failures} test(s) failed"
  exit 1
fi
