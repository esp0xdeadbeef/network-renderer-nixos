#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${repo_root}/tests/lib/test-common.sh"

# External tests first (matches how this repo is used in prod).
"${repo_root}/tests/cases/external-examples.sh"

# Renderer-level validation (no VM boot): VLAN trunk lanes should synthesize VLAN netdevs.
"${repo_root}/tests/cases/vlan-trunk-lanes.sh"

# Renderer must expose site-scoped CPM outputs (overlays/ipv6/routing) without guessing.
"${repo_root}/tests/cases/site-projections.sh"

# Regression: rendered host veth names must be globally unique and dual-ISP cores must be disjoint.
"${repo_root}/tests/cases/host-veth-consumer-sufficiency.sh"

# render-all.sh used to fail-fast on warnings, which makes it hard to use for
# scanning external examples (some warning alarms are upstream/missing CPM data).
# Keep a smoke test that ensures render-all can run a known-warning example and
# still exit 0 by default.
labs_root="$(flake_input_path network-labs)"
if [[ -d "${labs_root}/examples/multi-enterprise" ]]; then
  echo "==> Smoke: render-all.sh should not fail on warnings by default"
  "${repo_root}/render-all.sh" "${labs_root}/examples/multi-enterprise"
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
"${repo_root}/tests/cases/passing-fixtures.sh" "$@"

# Regression: local multi-enterprise dual-wan overlay examples must render.
"${repo_root}/tests/test-dual-wan-branch-overlay.sh"

# Regression: strict renderer must fail when required WAN group binding is absent.
"${repo_root}/tests/test-missing-wan-group-assignment.sh"

# Regression: multi-WAN external endpoint bindings must render policy rules.
"${repo_root}/tests/test-multi-wan-firewall.sh"

# Regression: WAN-exposed services must synthesize concrete DNAT rules.
"${repo_root}/tests/test-port-forward-rendering.sh"

# Regression: DNS runtime targets must be able to render authoritative local zones/records.
"${repo_root}/tests/test-dns-local-records.sh"

# Regression: runtime targets must be able to render modeled mDNS reflector settings.
"${repo_root}/tests/test-mdns-service.sh"

# Regression: exit cores must receive return-path host routes for remote transit endpoints.
"${repo_root}/tests/test-transit-endpoint-return-routes.sh"
