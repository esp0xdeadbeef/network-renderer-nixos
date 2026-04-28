#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

source "${repo_root}/tests/lib/test-common.sh"

example_root="$(flake_input_path network-labs)/examples/s-router-test-three-site"
intent_path="${example_root}/intent.nix"
inventory_path="${example_root}/inventory-nixos.nix"

REPO_ROOT="${repo_root}" \
INTENT_PATH="${intent_path}" \
INVENTORY_PATH="${inventory_path}" \
  nix eval \
    --extra-experimental-features 'nix-command flakes' \
    --impure --expr '
      let
        flake = builtins.getFlake ("path:" + builtins.getEnv "REPO_ROOT");
        builtContainers = flake.lib.containers.buildForBox {
          boxName = "s-router-test";
          system = "x86_64-linux";
          intentPath = builtins.getEnv "INTENT_PATH";
          inventoryPath = builtins.getEnv "INVENTORY_PATH";
        };
        cfg =
          (flake.inputs.nixpkgs.lib.nixosSystem {
            system = "x86_64-linux";
            modules = [ builtContainers."b-router-access-hostile".config ];
          }).config;
        coreCfg =
          (flake.inputs.nixpkgs.lib.nixosSystem {
            system = "x86_64-linux";
            modules = [ builtContainers."b-router-core-nebula".config ];
          }).config;
        script =
          builtins.readFile cfg.systemd.services."radvd-generate-tenant-hostile".serviceConfig.ExecStart;
        tenantNetwork = cfg.systemd.network.networks."10-tenant-hostile";
        addresses = tenantNetwork.address or [ ];
        routes = tenantNetwork.routes or [ ];
        coreUpstreamRoutes = coreCfg.systemd.network.networks."10-upstream".routes or [ ];
        coreServiceNames = builtins.attrNames coreCfg.systemd.services;
        hasDelegatedRouteService =
          builtins.any
            (name: builtins.match "s88-delegated-prefix-route-upstream-.*" name != null)
            coreServiceNames;
        hasHostileGuaOnlinkRoute =
          builtins.any (
            route:
              (route.Destination or null) == "2a01:4f8:1c17:b337::/64"
              && (route.Scope or null) == "link"
              && !(route ? Gateway)
          ) routes;
        hasHardcodedHostileRaPrefix =
          builtins.match ".*2a01:4f8:1c17:b337::/64.*" script != null;
        hasDynamicHostilePrefix =
          builtins.match ".*?/run/secrets/access-node-ipv6-prefix-espbranch-site-b-b-router-access-hostile.*" script != null;
        hasStaleCoreMainRoute =
          builtins.any (
            route:
              (route.Destination or null) == "2a01:04f8:1c17:b337:0000:0000:0000:0000/64"
              && !(route ? Table)
          ) coreUpstreamRoutes;
      in
        hasDynamicHostilePrefix
        && !hasHardcodedHostileRaPrefix
        && !hasHostileGuaOnlinkRoute
        && hasDelegatedRouteService
        && !hasStaleCoreMainRoute
        && !(builtins.elem "2a01:4f8:1c17:b337::1/64" addresses)
    ' | grep -qx true

pass "hostile-gua-advertisements"
