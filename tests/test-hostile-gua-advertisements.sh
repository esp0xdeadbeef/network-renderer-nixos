#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

source "${repo_root}/tests/lib/test-common.sh"

example_root="${repo_root}/tests/fixtures/s-router-overlay-dns-lane-policy"
intent_path="${example_root}/intent.nix"
inventory_path="${example_root}/inventory-nixos.nix"

nix_eval_true_or_fail "hostile-gua-advertisements" env REPO_ROOT="${repo_root}" \
INTENT_PATH="${intent_path}" \
INVENTORY_PATH="${inventory_path}" \
  nix eval \
    --extra-experimental-features 'nix-command flakes' \
    --impure --expr '
      let
        flake = builtins.getFlake ("path:" + builtins.getEnv "REPO_ROOT");
        builtContainers = import (builtins.getEnv "REPO_ROOT" + "/tests/nix/build-containers-from-paths.nix") {
          boxName = "s-router-test";
          system = "x86_64-linux";
        };
        hetznerContainers = import (builtins.getEnv "REPO_ROOT" + "/tests/nix/build-containers-from-paths.nix") {
          boxName = "s-router-hetzner-anywhere";
          system = "x86_64-linux";
        };
        cfg =
          (flake.inputs.nixpkgs.lib.nixosSystem {
            system = "x86_64-linux";
            modules = [ builtContainers."b-router-access-hostile".config ];
          }).config;
        hetznerCoreCfg =
          (flake.inputs.nixpkgs.lib.nixosSystem {
            system = "x86_64-linux";
            modules = [ hetznerContainers."c-router-core".config ];
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
        hetznerServiceNames = builtins.attrNames hetznerCoreCfg.systemd.services;
        hasDelegatedRouteService =
          builtins.any
            (name: builtins.match "s88-delegated-prefix-route-core-up-egress-.*" name != null)
            coreServiceNames;
        hetznerDelegatedRouteScripts =
          map
            (name: builtins.readFile hetznerCoreCfg.systemd.services.${name}.serviceConfig.ExecStart)
            (builtins.filter
              (name: builtins.match "s88-delegated-prefix-route-.*" name != null)
              hetznerServiceNames);
        hostileSourceFile = "/run/secrets/access-node-ipv6-prefix-espbranch-site-b-b-router-access-hostile";
        hetznerHostileRouteScripts =
          builtins.filter
            (script: builtins.match (".*" + hostileSourceFile + ".*") script != null)
            hetznerDelegatedRouteScripts;
        hetznerHostileRouteDoesNotUseEth0 =
          !(builtins.any
            (script: builtins.match (".*" + hostileSourceFile + ".*interface=eth0.*") script != null)
            hetznerDelegatedRouteScripts);
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
        && hetznerHostileRouteDoesNotUseEth0
        && !hasStaleCoreMainRoute
        && !(builtins.elem "2a01:4f8:1c17:b337::1/64" addresses)
    '

pass "hostile-gua-advertisements"
