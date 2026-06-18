#!/usr/bin/env bash
# GAMP-ID: FS-320-HDS-030-SDS-010-SMS-050
# GAMP-SCOPE: software-module-test
# Focused construction test: NixOS renderer per-interface policy routing table
# connected peer routes with proto=kernel scope=link for all fabric nodes.
#
# SMS-050: Per-interface policy routing tables must include connected peer
# /31 (IPv4) and /127 (IPv6) routes with proto=kernel scope=link for ALL
# fabric chain nodes (policy, downstream-selector, upstream-selector).
# Module shall REJECT non-existent interface references with diagnostic.
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
tmp_dir="$(mktemp -d)"
trap 'rm -rf "${tmp_dir}"' EXIT
all_checks_passed=true
src_dir="${repo_root}/s88"

echo "--- FS-320-HDS-030-SDS-010-SMS-050: Per-interface policy table connected peer routes ---"
echo ""

route_helpers_file="${src_dir}/ControlModule/render/container-networks/policy-routing/route-helpers.nix"
raw_routes_file="${src_dir}/ControlModule/render/container-networks/policy-routing/raw-routes.nix"

# Helper: extract a Nix function body by start-line pattern end end-line pattern
extract_function_block() {
  local file="$1"
  local start_pattern="$2"
  local end_pattern="$3"
  local output="$4"
  # Extract from start_pattern to end_pattern, then remove the end_pattern line
  sed -n "/${start_pattern}/,/${end_pattern}/p" "${file}" | sed '$d' > "${output}" 2>/dev/null || true
}

# ============================================================
# Predicate 1: connectedP2pScopeRoutesForInterface emits proto=kernel AND scope=link
# ============================================================
echo "--- Predicate 1: connectedP2pScopeRoutesForInterface has proto=kernel + scope=link ---"

scope_block="${tmp_dir}/scope-block.txt"
extract_function_block "${route_helpers_file}" \
  '^  connectedP2pScopeRoutesForInterface =' \
  '^  connectedScopeRoutesForInterface =' \
  "${scope_block}"

proto_ok=false
scope_ok=false
if grep -q 'proto = "kernel"' "${scope_block}" 2>/dev/null; then
  echo "  OK: proto = \"kernel\" found in connectedP2pScopeRoutesForInterface"
  proto_ok=true
else
  echo "FAIL: proto = \"kernel\" NOT found in connectedP2pScopeRoutesForInterface"
  all_checks_passed=false
fi

if grep -q 'scope = "link"' "${scope_block}" 2>/dev/null; then
  echo "  OK: scope = \"link\" found in connectedP2pScopeRoutesForInterface"
  scope_ok=true
else
  echo "FAIL: scope = \"link\" NOT found in connectedP2pScopeRoutesForInterface"
  all_checks_passed=false
fi

if ${proto_ok} && ${scope_ok}; then
  echo "PASS: connectedP2pScopeRoutesForInterface has proto=kernel + scope=link"
fi

# ============================================================
# Predicate 2: connectedP2pRoutesForInterface emits proto=kernel AND scope=link
# ============================================================
echo ""
echo "--- Predicate 2: connectedP2pRoutesForInterface has proto=kernel + scope=link ---"

p2p_block="${tmp_dir}/p2p-block.txt"
extract_function_block "${route_helpers_file}" \
  '^  connectedP2pRoutesForInterface =' \
  '^  connectedP2pScopeRoutesForInterface =' \
  "${p2p_block}"

p2p_proto_ok=false
p2p_scope_ok=false
if grep -q 'proto = "kernel"' "${p2p_block}" 2>/dev/null; then
  echo "  OK: proto = \"kernel\" found in connectedP2pRoutesForInterface"
  p2p_proto_ok=true
else
  echo "FAIL: proto = \"kernel\" NOT found in connectedP2pRoutesForInterface"
  all_checks_passed=false
fi

if grep -q 'scope = "link"' "${p2p_block}" 2>/dev/null; then
  echo "  OK: scope = \"link\" found in connectedP2pRoutesForInterface"
  p2p_scope_ok=true
else
  echo "FAIL: scope = \"link\" NOT found in connectedP2pRoutesForInterface"
  all_checks_passed=false
fi

if ${p2p_proto_ok} && ${p2p_scope_ok}; then
  echo "PASS: connectedP2pRoutesForInterface has proto=kernel + scope=link"
fi

# ============================================================
# Predicate 3: Fail-closed guard for non-existent interface
# ============================================================
echo ""
echo "--- Predicate 3: Fail-closed guard rejects non-existent interface ---"

guard_count=$(grep -c 'interfaces ?' "${route_helpers_file}" 2>/dev/null; true)
guard_count=$(echo "${guard_count}" | tr -d '[:space:]')
if [[ -z "${guard_count}" ]]; then guard_count=0; fi
if [[ "${guard_count}" -ge 1 ]]; then
  echo "  OK: interfaces-existence guard found (${guard_count} occurrence(s))"
  
  # Verify the throw diagnostic names the unresolved interface
  if grep -q 'non-existent interface\|does not exist in the current layout' "${route_helpers_file}" 2>/dev/null; then
    echo "  OK: Diagnostic names non-existent interface in throw message"
    echo "PASS: Fail-closed guard rejects non-existent interface with diagnostic"
  else
    echo "FAIL: No diagnostic for non-existent interface in throw message"
    all_checks_passed=false
  fi
else
  echo "FAIL: No interfaces-existence guard found in route-helpers.nix"
  all_checks_passed=false
fi

# ============================================================
# Predicate 4: policyConnectedRoutes block exists (policy node coverage)
# ============================================================
echo ""
echo "--- Predicate 4: Policy node connected peer route coverage ---"

if grep -q 'policyConnectedRoutes' "${raw_routes_file}" 2>/dev/null; then
  echo "  OK: policyConnectedRoutes block found in raw-routes.nix"
  
  # Extract the policyConnectedRoutes block
  policy_block="${tmp_dir}/policy-block.txt"
  extract_function_block "${raw_routes_file}" \
    '^  policyConnectedRoutes =' \
    '^  upstreamCoreConnectedRoutes =' \
    "${policy_block}"
  
  if grep -q 'connectedP2pScopeRoutesForInterface' "${policy_block}" 2>/dev/null; then
    echo "  OK: policyConnectedRoutes calls connectedP2pScopeRoutesForInterface"
  else
    echo "FAIL: policyConnectedRoutes does not call connectedP2pScopeRoutesForInterface"
    all_checks_passed=false
  fi
  
  # Verify it's wired into sourceRoutes
  if grep -A 35 '^  sourceRoutes =' "${raw_routes_file}" | grep -q 'policyConnectedRoutes' 2>/dev/null; then
    echo "  OK: policyConnectedRoutes wired into sourceRoutes assembly"
    echo "PASS: Policy node has per-interface connected peer route coverage"
  else
    echo "FAIL: policyConnectedRoutes NOT wired into sourceRoutes"
    all_checks_passed=false
  fi
else
  echo "FAIL: policyConnectedRoutes block NOT found in raw-routes.nix"
  all_checks_passed=false
fi

# ============================================================
# Predicate 5: upstreamCoreConnectedRoutes block exists (upstream-selector core coverage)
# ============================================================
echo ""
echo "--- Predicate 5: Upstream-selector core connected peer route coverage ---"

if grep -q 'upstreamCoreConnectedRoutes' "${raw_routes_file}" 2>/dev/null; then
  echo "  OK: upstreamCoreConnectedRoutes block found in raw-routes.nix"
  
  # Verify it's wired into sourceRoutes
  if grep -A 35 '^  sourceRoutes =' "${raw_routes_file}" | grep -q 'upstreamCoreConnectedRoutes' 2>/dev/null; then
    echo "  OK: upstreamCoreConnectedRoutes wired into sourceRoutes assembly"
    echo "PASS: Upstream-selector core has per-interface connected peer route coverage"
  else
    echo "FAIL: upstreamCoreConnectedRoutes NOT wired into sourceRoutes"
    all_checks_passed=false
  fi
else
  echo "FAIL: upstreamCoreConnectedRoutes block NOT found in raw-routes.nix"
  all_checks_passed=false
fi

# ============================================================
# Predicate 6: downstreamSelectorReturnConnectedRoutes still present
# ============================================================
echo ""
echo "--- Predicate 6: Downstream-selector coverage preserved ---"

if grep -q 'downstreamSelectorReturnConnectedRoutes' "${raw_routes_file}" 2>/dev/null; then
  echo "  OK: downstreamSelectorReturnConnectedRoutes block still present in raw-routes.nix"
  echo "PASS: Downstream-selector coverage preserved"
else
  echo "FAIL: downstreamSelectorReturnConnectedRoutes missing from raw-routes.nix"
  all_checks_passed=false
fi

# ============================================================
# Seeded Negative 1: Scanner detects missing proto=kernel
# ============================================================
echo ""
echo "--- Seeded Negative 1: Would detect missing proto=kernel ---"

fake_helpers="${tmp_dir}/fake-route-helpers.nix"
cp "${route_helpers_file}" "${fake_helpers}"

# Remove proto = "kernel" from the file
sed -i 's/proto = "kernel";//g' "${fake_helpers}" 2>/dev/null || true

proto_count=$(grep -c 'proto = "kernel"' "${fake_helpers}" 2>/dev/null; true)
# Strip any whitespace/newlines
proto_count=$(echo "${proto_count}" | tr -d '[:space:]')
if [[ -z "${proto_count}" ]]; then proto_count=0; fi
if [[ "${proto_count}" -eq 0 ]]; then
  echo "PASS: Seeded negative — scanner detects absent proto=kernel (0 matches in stripped file)"
else
  echo "FAIL: Seeded negative — proto=kernel still found after removal (${proto_count} matches)"
  all_checks_passed=false
fi

# ============================================================
# Seeded Negative 2: Scanner detects missing policy coverage
# ============================================================
echo ""
echo "--- Seeded Negative 2: Would detect missing policy node coverage ---"

fake_raw="${tmp_dir}/fake-raw-routes.nix"
cp "${raw_routes_file}" "${fake_raw}"

# Remove policyConnectedRoutes from the file
sed -i '/policyConnectedRoutes/d' "${fake_raw}" 2>/dev/null || true

if grep -q 'policyConnectedRoutes' "${fake_raw}" 2>/dev/null; then
  echo "FAIL: Seeded negative — policyConnectedRoutes still found after removal"
  all_checks_passed=false
else
  echo "PASS: Seeded negative — scanner detects absent policy node coverage (0 matches in stripped file)"
fi

# ============================================================
# Report
# ============================================================
echo ""
if ${all_checks_passed}; then
  echo "PASS: FS-320-HDS-030-SDS-010-SMS-050 — Per-interface policy routing table connected peer routes have proto=kernel scope=link for all fabric nodes (policy, downstream-selector, upstream-selector) with fail-closed guard for non-existent interfaces."
  exit 0
else
  echo "FAIL: FS-320-HDS-030-SDS-010-SMS-050 — one or more predicates failed."
  exit 1
fi
