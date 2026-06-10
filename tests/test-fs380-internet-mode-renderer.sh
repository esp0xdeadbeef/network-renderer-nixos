#!/usr/bin/env bash
# GAMP-ID: FS-380-HDS-010-SDS-010-SMS-050-CMC-001
# GAMP-ID: FS-400-HDS-010-SDS-010-SMS-060-CMC-001
# GAMP-ID: FS-410-HDS-010-SDS-010-SMS-050-CMC-001
# SMS-050/060: Renderer internet mode verification — module-level (mock CPM)
# Verifies that render-ruleset.nix generates correct NAT masquerade rules
# for both IPv4 and IPv6 from mock CPM internet mode data.
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# --- IPv4: mock privateNat44 with client prefixes ---
echo "=== Test IPv4 NAT from mock CPM privateNat44 ==="

ipv4_result="$(mktemp)"
trap 'rm -f "${ipv4_result}"' EXIT

REPO_ROOT="${repo_root}" nix eval \
  --extra-experimental-features 'nix-command flakes' \
  --impure --raw --expr '
    let
      repoRoot = builtins.getEnv "REPO_ROOT";
      flake = builtins.getFlake ("path:" + repoRoot);
      lib = flake.inputs.nixpkgs.lib;
      renderRuleset = import (repoRoot + "/s88/ControlModule/firewall/emission/render-ruleset.nix") {
        inherit lib;
      };
      # Mock CPM internetModes.privateNat44 for the client tenant
      result = renderRuleset {
        tableName = "edge_nat";
        forwardPolicy = "drop";
        natInterfaces = [ "ens80" ];
        nat4SourcePrefixes = [ "10.20.20.0/24" "10.50.20.0/24" ];
        nat6Interfaces = [ ];
        nat6SourcePrefixes = [ ];
      };
    in result
  ' > "${ipv4_result}"

if ! grep -q 'oifname "ens80" ip saddr { 10.20.20.0/24, 10.50.20.0/24 } masquerade' "${ipv4_result}"; then
  echo "FAIL: IPv4 masquerade rule missing or wrong source prefixes"
  echo "Got:"
  grep 'masquerade' "${ipv4_result}" || echo "(no masquerade rule found)"
  exit 1
fi
echo "PASS: IPv4 masquerade covers client prefixes"

# --- IPv4: empty source prefixes = blanket masquerade (correct) ---
echo "=== Test IPv4 blanket masquerade when source prefixes empty ==="

ipv4_empty="$(mktemp)"
trap 'rm -f "${ipv4_empty}"' EXIT

REPO_ROOT="${repo_root}" nix eval \
  --extra-experimental-features 'nix-command flakes' \
  --impure --raw --expr '
    let
      repoRoot = builtins.getEnv "REPO_ROOT";
      flake = builtins.getFlake ("path:" + repoRoot);
      lib = flake.inputs.nixpkgs.lib;
      renderRuleset = import (repoRoot + "/s88/ControlModule/firewall/emission/render-ruleset.nix") {
        inherit lib;
      };
      result = renderRuleset {
        tableName = "edge_nat";
        forwardPolicy = "drop";
        natInterfaces = [ "ens80" ];
        nat4SourcePrefixes = [ ];
        nat6Interfaces = [ ];
        nat6SourcePrefixes = [ ];
      };
    in result
  ' > "${ipv4_empty}"

if ! grep -q 'oifname "ens80" masquerade' "${ipv4_empty}"; then
  echo "FAIL: blanket masquerade missing on WAN interface"
  grep 'masquerade' "${ipv4_empty}" || echo "(no masquerade rule found)"
  exit 1
fi
echo "PASS: blanket masquerade on WAN when no source prefixes (correct renderer behavior)"

# --- IPv6: mock ulaNat66 with ULA prefixes ---
echo "=== Test IPv6 NAT66 from mock CPM ulaNat66 ==="

ipv6_result="$(mktemp)"
trap 'rm -f "${ipv6_result}"' EXIT

REPO_ROOT="${repo_root}" nix eval \
  --extra-experimental-features 'nix-command flakes' \
  --impure --raw --expr '
    let
      repoRoot = builtins.getEnv "REPO_ROOT";
      flake = builtins.getFlake ("path:" + repoRoot);
      lib = flake.inputs.nixpkgs.lib;
      renderRuleset = import (repoRoot + "/s88/ControlModule/firewall/emission/render-ruleset.nix") {
        inherit lib;
      };
      # Mock CPM internetModes.ulaNat66 for the client tenant
      result = renderRuleset {
        tableName = "edge_nat";
        forwardPolicy = "drop";
        natInterfaces = [ ];
        nat4SourcePrefixes = [ ];
        nat6Interfaces = [ "ens80" ];
        nat6SourcePrefixes = [ "fd42:dead:beef:20::/64" ];
      };
    in result
  ' > "${ipv6_result}"

if ! grep -q 'oifname "ens80" ip6 saddr.*fd42:dead:beef:20::/64.*masquerade' "${ipv6_result}"; then
  echo "FAIL: IPv6 masquerade rule missing or wrong source prefix"
  echo "Got:"
  grep 'masquerade' "${ipv6_result}" || echo "(no masquerade rule found)"
  exit 1
fi
echo "PASS: IPv6 NAT66 covers ULA client prefix"

echo ""
echo "ALL SMS-050/060 CMC TESTS PASSED"
