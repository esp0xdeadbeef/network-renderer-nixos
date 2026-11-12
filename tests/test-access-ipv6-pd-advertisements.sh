#!/usr/bin/env bash
# GAMP-ID: FS-800-HDS-030-SDS-020-SMS-040 (access IPv6-PD downstream delegation)
#
# CROSS-REPO DEPENDENCY (known red at upstream HEAD, green at the pinned lock):
# this fixture models per-access uplink p2p links
#   p2p-s-router-policy-s-router-upstream-selector--access-s-router-access-*--uplink-wan
# which network-control-plane-model generates at the revision recorded in
# flake.lock. A newer model revision changes that link naming, so the inventory
# lint rejects the fixture with
#
#   references unknown forwarding-model site link 'p2p-...--uplink-wan'
#
# flake.lock is gitignored, so CI regenerates it and resolves upstream HEAD,
# while a developer checkout uses the recorded pin. Keep this case failing
# closed rather than weakening the inventory: the fixture must be migrated to
# whatever link shape the owning model layer emits. Owner:
# network-control-plane-model (link generation) plus this fixture.
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${repo_root}/tests/lib/test-common.sh"

intent_path="${repo_root}/tests/fixtures/single-wan-ipv6-pd/intent.nix"
inventory_path="${repo_root}/tests/fixtures/single-wan-ipv6-pd/inventory-nixos.nix"

[[ -f "${intent_path}" ]] || { echo "missing intent: ${intent_path}" >&2; exit 1; }
[[ -f "${inventory_path}" ]] || { echo "missing inventory: ${inventory_path}" >&2; exit 1; }

nix_eval_true_or_fail "access-ipv6-pd-advertisements" env REPO_ROOT="${repo_root}" \
INTENT_PATH="${intent_path}" \
INVENTORY_PATH="${inventory_path}" \
  nix eval \
    --extra-experimental-features 'nix-command flakes' \
    --impure --expr '
      let
        flake = builtins.getFlake ("path:" + builtins.getEnv "REPO_ROOT");
        builtContainers = import (builtins.getEnv "REPO_ROOT" + "/tests/nix/build-containers-from-paths.nix") {
          boxName = "lab-host";
          system = "x86_64-linux";
        };
        cfg =
          (flake.inputs.nixpkgs.lib.nixosSystem {
            system = "x86_64-linux";
            modules = [ builtContainers."s-router-access-client".config ];
          }).config;
        service = cfg.systemd.services."radvd-generate-tenant-client";
        script = builtins.readFile service.serviceConfig.ExecStart;
        pathUnit = cfg.systemd.paths."radvd-prefix-tenant-client" or { };
        pathConfig = pathUnit.pathConfig or { };
      in
        builtins.match ".*?/run/s88-ipv6-pd/wan.prefix.*" script != null
        && builtins.match ".*?\"56\" \"64\" \"1\".*" script != null
        && (pathConfig.PathExists or null) == "/run/s88-ipv6-pd/wan.prefix"
        && (pathConfig.PathChanged or null) == "/run/s88-ipv6-pd/wan.prefix"
        && (pathConfig.Unit or null) == "radvd-generate-tenant-client.service"
    '

echo "PASS access-ipv6-pd-advertisements"
