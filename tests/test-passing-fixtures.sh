#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${repo_root}/tests/lib/test-common.sh"

"${repo_root}/tests/test-nix-file-loc.sh"

# ControlModules are called by Unit/Equipment/Site with narrow inputs.
bash "${repo_root}/tests/test-controlmodule-boundary.sh"
bash "${repo_root}/tests/test-s88-call-flow.sh"
bash "${repo_root}/tests/test-s88-call-flow-profiler.sh"

# Container firewall rules must use rendered Linux ifnames, not long logical ports.
bash "${repo_root}/tests/test-container-firewall-ifname-limit.sh"

# Clean renderer outputs must not hide alarms/warnings, and warning/error paths
# must visibly surface when produced.
bash "${repo_root}/tests/test-warning-alarm-contract.sh"

# Test assertions must print the failed contract, not just a silent pipeline exit.
bash "${repo_root}/tests/test-loud-test-failures.sh"

# External tests first (matches how this repo is used in prod).
"${repo_root}/tests/cases/external-examples.sh"

# Renderer-level validation (no VM boot): VLAN trunk lanes should synthesize VLAN netdevs.
"${repo_root}/tests/cases/vlan-trunk-lanes.sh"

# Renderer-level validation: WAN uplinks on VLAN 4/5 keep DHCP/RA host behavior.
bash "${repo_root}/tests/test-host-uplink-vlan-dhcp.sh"

# Renderer API validation: host builds own container defaults and selection.
bash "${repo_root}/tests/test-host-build-container-selection.sh"

# Renderer-level validation: policy nft rules must not cross tenant/zone p2p lanes.
bash "${repo_root}/tests/test-policy-zone-firewall-scoping.sh"

# Renderer must expose site-scoped CPM outputs (overlays/ipv6/routing) without guessing.
"${repo_root}/tests/cases/site-projections.sh"

# Regression: rendered host veth names must be globally unique and dual-ISP cores must be disjoint.
"${repo_root}/tests/cases/host-veth-consumer-sufficiency.sh"

# Multi-enterprise selector forwarding is explicit fail-closed when CPM provides
# selector forwarding mode plus an empty rules list. The renderer must not turn
# that explicit policy into warning alarms.
labs_root="$(flake_input_path network-labs)"
if [[ -d "${labs_root}/examples/multi-enterprise" ]]; then
  echo "==> Strict: multi-enterprise must render without selector warning alarms"
  FAIL_ON_WARNINGS=1 "${repo_root}/render-all.sh" "${labs_root}/examples/multi-enterprise"
fi

# Regression: vm build API exists and returns an attrset (no lambda-vs-set drift).
echo "==> Smoke: renderer.vm.build API shape"
nix eval \
  --extra-experimental-features 'nix-command flakes' \
  --impure --raw \
  --expr '
    let
      f = builtins.getFlake (toString '"${repo_root}"');
      s = builtins.currentSystem;
      exampleDir = f.inputs.network-labs.outPath + "/examples/single-wan";
      v = f.libBySystem.${s}.renderer.vm.build {
        intentPath = exampleDir + "/intent.nix";
        inventoryPath = exampleDir + "/inventory-nixos.nix";
        boxName = "lab-host";
      };
    in
    v.boxName
  ' >/dev/null

# Keep at least one in-repo fixture for repeatable CI-like checks.
bash "${repo_root}/tests/cases/passing-fixtures.sh" "$@"

# Regression: local multi-enterprise dual-wan overlay examples must render.
bash "${repo_root}/tests/test-dual-wan-branch-overlay.sh"
bash "${repo_root}/tests/test-hostile-dns-east-west.sh"

# Regression: policy ingress lanes must render DNS-service reachability routes.
bash "${repo_root}/tests/test-dns-service-policy-routes.sh"

# Regression: strict renderer must fail when required WAN group binding is absent.
bash "${repo_root}/tests/test-missing-wan-group-assignment.sh"

# Regression: multi-WAN external endpoint bindings must render policy rules.
bash "${repo_root}/tests/test-multi-wan-firewall.sh"

# Regression: WAN-exposed services must synthesize concrete DNAT rules.
bash "${repo_root}/tests/test-port-forward-rendering.sh"
bash "${repo_root}/tests/test-public-overlay-service-forwarding.sh"
bash "${repo_root}/tests/test-public-ingress-module.sh"

# Regression: DNS runtime targets must be able to render authoritative local zones/records.
bash "${repo_root}/tests/test-dns-local-records.sh"

# Regression: runtime targets must be able to render modeled mDNS reflector settings.
"${repo_root}/tests/test-mdns-service.sh"

# Regression: exit cores must receive return-path host routes for remote transit endpoints.
"${repo_root}/tests/test-transit-endpoint-return-routes.sh"
