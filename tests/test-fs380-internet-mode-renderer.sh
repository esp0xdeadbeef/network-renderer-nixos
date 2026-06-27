#!/usr/bin/env bash
# GAMP-ID: FS-380-HDS-020-SDS-010-SMS-050-CMC-001
# GAMP-ID: FS-400-HDS-010-SDS-010-SMS-060-CMC-001
# GAMP-ID: FS-410-HDS-010-SDS-010-SMS-050-CMC-001
# SMS-050/060: Renderer internet mode verification — module-level (mock CPM)
# Verifies that render-ruleset.nix generates correct NAT masquerade rules
# for both IPv4 and IPv6 from mock CPM internet mode data.
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
tmp_files=()
cleanup() {
  if ((${#tmp_files[@]} > 0)); then
    rm -f "${tmp_files[@]}"
  fi
}
trap cleanup EXIT

new_tmp() {
  local path
  path="$(mktemp)"
  tmp_files+=("${path}")
  printf '%s\n' "${path}"
}

# --- IPv4: mock privateNat44 with client prefixes ---
echo "=== Test IPv4 NAT from mock CPM privateNat44 ==="

ipv4_result="$(new_tmp)"

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

ipv4_empty="$(new_tmp)"

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

ipv6_result="$(new_tmp)"

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

# --- IPv6 routed GUA: no NAT66 for routed client GUA ---
echo "=== Test IPv6 routed GUA stays untranslated ==="

routed_gua_result="$(new_tmp)"
routed_gua_negative="$(new_tmp)"

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
      # Mock CPM routedClientGua: renderer receives routes, not NAT66 intent.
      result = renderRuleset {
        tableName = "edge_nat";
        forwardPolicy = "drop";
        forwardRules = [
          "ip6 saddr 2001:db8:20::/64 accept comment \"FS-410-routed-gua-forward\""
        ];
        natInterfaces = [ ];
        nat4SourcePrefixes = [ ];
        nat6Interfaces = [ ];
        nat6SourcePrefixes = [ ];
      };
    in result
  ' > "${routed_gua_result}"

cat >"${routed_gua_negative}" <<'EOF_NEG'
table ip6 nat {
  chain postrouting {
    type nat hook postrouting priority 100; policy accept;
    oifname "ens80" ip6 saddr 2001:db8:20::/64 masquerade
  }
}
EOF_NEG

has_routed_gua_nat66_violation() {
  grep -Eq 'ip6 saddr.*2001:db8:20::/64.*masquerade' "$1"
}

if has_routed_gua_nat66_violation "${routed_gua_result}"; then
  echo "FAIL: routed GUA mock produced NAT66 masquerade"
  grep 'masquerade' "${routed_gua_result}" || true
  exit 1
fi
if ! has_routed_gua_nat66_violation "${routed_gua_negative}"; then
  echo "FAIL: seeded routed GUA NAT66 violation was not detected"
  cat "${routed_gua_negative}"
  exit 1
fi
echo "PASS: routed GUA remains untranslated and seeded NAT66 violation is detected"

# --- IPv6 host128: no downstream route export for host-only /128 ---
echo "=== Test host-only /128 downstream export violation detection ==="

host128_positive="$(new_tmp)"
host128_negative="$(new_tmp)"
cat >"${host128_positive}" <<'EOF_POS'
{
  "routes": [
    {
      "dst": "2001:db8:128::2/128",
      "intent": {
        "kind": "uplink-learned-reachability",
        "source": "explicit-uplink"
      }
    }
  ]
}
EOF_POS
cat >"${host128_negative}" <<'EOF_NEG'
{
  "routes": [
    {
      "dst": "2001:db8:128::1/128",
      "intent": {
        "kind": "internal-reachability",
        "accessNode": "client"
      }
    }
  ]
}
EOF_NEG

has_host128_downstream_export_violation() {
  python3 - "$1" <<'PY'
import json
import sys

with open(sys.argv[1], encoding="utf-8") as handle:
    data = json.load(handle)

for route in data.get("routes", []):
    dst = route.get("dst") or ""
    intent = route.get("intent") or {}
    if not dst.startswith("2001:db8:128:"):
        continue
    if intent.get("kind") in {
        "connected-reachability",
        "internal-reachability",
        "runtime-routed-prefix-return",
    }:
        sys.exit(0)
    downstream_export = intent.get("downstreamExport") or {}
    if downstream_export.get("allowed") is True:
        sys.exit(0)
sys.exit(1)
PY
}

if has_host128_downstream_export_violation "${host128_positive}"; then
  echo "FAIL: host-only /128 uplink-learned route was misclassified as downstream export"
  cat "${host128_positive}"
  exit 1
fi
if ! has_host128_downstream_export_violation "${host128_negative}"; then
  echo "FAIL: seeded host-only /128 downstream export violation was not detected"
  cat "${host128_negative}"
  exit 1
fi
echo "PASS: host-only /128 downstream export seeded negative is detected"

echo ""
echo "ALL SMS-050/060 CMC TESTS PASSED"
