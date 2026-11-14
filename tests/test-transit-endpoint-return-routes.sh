#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

source "${repo_root}/tests/lib/test-common.sh"

example_root="${repo_root}/tests/fixtures/dual-wan-branch-overlay-bgp"
intent_path="${example_root}/intent.nix"
inventory_path="${example_root}/inventory-nixos.nix"

[[ -f "${intent_path}" ]] || fail "missing intent fixture: ${intent_path}"
[[ -f "${inventory_path}" ]] || fail "missing inventory fixture: ${inventory_path}"

nix_eval_true_or_fail "transit-endpoint-return-routes:dual-wan" \
  env REPO_ROOT="${repo_root}" \
    INTENT_PATH="${intent_path}" \
    INVENTORY_PATH="${inventory_path}" \
    nix eval \
    --extra-experimental-features 'nix-command flakes' \
    --impure --expr '
      let
        flake = builtins.getFlake ("path:" + builtins.getEnv "REPO_ROOT");
        host = import (builtins.getEnv "REPO_ROOT" + "/tests/nix/build-host-from-paths.nix") {
          selector = "lab-host";
          system = "x86_64-linux";
          intentPath = builtins.getEnv "INTENT_PATH";
          inventoryPath = builtins.getEnv "INVENTORY_PATH";
        };
        rendered = host.renderedHost.containers."s-router-core-isp-a";
        cfg =
          (flake.inputs.nixpkgs.lib.nixosSystem {
            system = "x86_64-linux";
            modules = [ rendered.config ];
          }).config;
        routes = cfg.systemd.network.networks."10-ens3".routes or [ ];
        hasRoute = destination: gateway:
          builtins.any
            (route:
              (route.Destination or null) == destination
              && (route.Gateway or null) == gateway)
            routes;
      in
        hasRoute "10.19.0.8/32" "10.10.0.9"
        && (
          hasRoute "fd42:dead:beef:1900:0000:0000:0000:0008/128" "fd42:dead:beef:1000:0:0:0:9"
          || hasRoute "fd42:dead:beef:1900:0:0:0:8/128" "fd42:dead:beef:1000:0:0:0:9"
        )
    '

nix_eval_true_or_fail "transit-endpoint-return-routes:s-router-test" \
  env REPO_ROOT="${repo_root}" \
    INTENT_PATH="${repo_root}/tests/fixtures/s-router-overlay-dns-lane-policy/intent.nix" \
    INVENTORY_PATH="${repo_root}/tests/fixtures/s-router-overlay-dns-lane-policy/inventory-nixos.nix" \
    nix eval \
    --extra-experimental-features 'nix-command flakes' \
    --impure --expr '
      let
        flake = builtins.getFlake ("path:" + builtins.getEnv "REPO_ROOT");
        testHost = import (builtins.getEnv "REPO_ROOT" + "/tests/nix/build-host-from-paths.nix") {
          selector = "s-router-test";
          system = "x86_64-linux";
          intentPath = builtins.getEnv "INTENT_PATH";
          inventoryPath = builtins.getEnv "INVENTORY_PATH";
        };
        hetznerHost = import (builtins.getEnv "REPO_ROOT" + "/tests/nix/build-host-from-paths.nix") {
          selector = "s-router-hetzner-anywhere";
          system = "x86_64-linux";
          intentPath = builtins.getEnv "INTENT_PATH";
          inventoryPath = builtins.getEnv "INVENTORY_PATH";
        };
        renderedBranchCore = testHost.renderedHost.containers."s-router-core-isp-b";
        renderedBranchNebulaCore = testHost.renderedHost.containers."b-router-core-nebula";
        renderedBranchUpstreamSelector = testHost.renderedHost.containers."b-router-upstream-selector";
        cfgBranchCore =
          (flake.inputs.nixpkgs.lib.nixosSystem {
            system = "x86_64-linux";
            modules = [ renderedBranchCore.config ];
          }).config;
        cfgBranchNebulaCore =
          (flake.inputs.nixpkgs.lib.nixosSystem {
            system = "x86_64-linux";
            modules = [ renderedBranchNebulaCore.config ];
          }).config;
        cfgBranchUpstreamSelector =
          (flake.inputs.nixpkgs.lib.nixosSystem {
            system = "x86_64-linux";
            modules = [ renderedBranchUpstreamSelector.config ];
          }).config;
        branchCoreNetworks = cfgBranchCore.systemd.network.networks;
        branchNebulaNetworks = cfgBranchNebulaCore.systemd.network.networks;
        branchUpstreamSelectorNetworks = cfgBranchUpstreamSelector.systemd.network.networks;
        hasMainRoute = routes: destination: gateway:
          builtins.any
            (route:
              (route.Destination or null) == destination
              && (route.Gateway or null) == gateway
              && !(builtins.hasAttr "Table" route))
            routes;
        # A point-to-point lane is realized as a connected prefix on this node
        # plus one on-link host route to the peer. The lane cannot be asserted
        # as a route to its own /31: that prefix contains the address of this node
        # (10.10.0.14/31 on s-router-core-isp-b), so such a route would point
        # the node at its own wire and the sibling check below asserts it does
        # not exist. What must hold is that the peer is reachable in the main
        # table with the peer as its on-link next hop.
        hasOnlinkPeerRoute = routes: peer: gateway:
          builtins.any
            (route:
              ((route.Destination or null) == (peer + "/32") || (route.Destination or null) == (peer + "/128"))
              && !(builtins.hasAttr "Table" route)
              && (route.Gateway or null) == gateway
              && (route.GatewayOnLink or false) == true)
            routes;
        hasMainRouteAnyNetwork = networks: destination: gateway:
          builtins.any
            (networkName: hasMainRoute (networks.${networkName}.routes or [ ]) destination gateway)
            (builtins.attrNames networks);
        hasRoute = routes: destination: gateway:
          builtins.any
            (route:
              (route.Destination or null) == destination
              && (route.Gateway or null) == gateway)
            routes;
        hasRouteAnyNetwork = networks: destination: gateway:
          builtins.any
            (networkName: hasRoute (networks.${networkName}.routes or [ ]) destination gateway)
            (builtins.attrNames networks);
        # FS-315: a generic default is installed only on a lane whose modeled
        # uplink offers one, so the overlay core must not install a main-table
        # default toward the overlay lane; its only defaults are the
        # policy-only delegated public-egress complements (FS-460), and the
        # delegated hostile prefix returns over the modeled policy lane toward
        # the hostile access node (FS-550), not as an underlay default route.
        nebHasNoMainGenericDefault =
          !(hasMainRouteAnyNetwork branchNebulaNetworks "0.0.0.0/0" "10.50.0.5")
          && !(hasMainRouteAnyNetwork branchNebulaNetworks "::/0" "fd42:dead:feed:1000:0:0:0:5")
          && !(builtins.any
            (networkName:
              builtins.any
                (route: (route.Destination or "") == "::/0" || (route.Destination or "") == "0.0.0.0/0")
                (builtins.filter (route: !(builtins.hasAttr "Table" route)) (branchNebulaNetworks.${networkName}.routes or [ ])))
            (builtins.attrNames branchNebulaNetworks));
        nebRoutes =
          builtins.concatMap
            (networkName: branchNebulaNetworks.${networkName}.routes or [ ])
            (builtins.attrNames branchNebulaNetworks);
        nebPolicyTableDefaults =
          builtins.any
            (table:
              builtins.any
                (route: (route.Destination or "") == "0.0.0.0/0" && (route.Table or null) == table && !(builtins.hasAttr "Gateway" route))
                nebRoutes
              && builtins.any
                (route: (route.Destination or "") == "::/0" && (route.Table or null) == table && !(builtins.hasAttr "Gateway" route))
                nebRoutes)
            (builtins.filter builtins.isInt (map (route: route.Table or null) nebRoutes));
        # FS-550: the hostile tenant is NOT terminated on the overlay core. The
        # overlay core is b-router-core-nebula, whose only lane toward the
        # hostile tenant is the east-west overlay uplink; the hostile access
        # node (and the delegated prefix it owns) sits behind the policy point,
        # whose modeled return lane is 10-pol-hostile-ew / its IPv6 twin. The
        # sibling case test-overlay-core-local-hostile-return-routes.sh already
        # asserts the own contract of the overlay core (no static hostile route, both
        # hostile prefixes scoped to one policy table with a main fallback, a
        # runtime install of the delegated prefix toward the modeled upstream
        # next hop). Here the return must exist toward the node that actually
        # peers with the hostile tenant.
        hostileDelegatedReturnOnPolicyLane =
          hasRouteAnyNetwork branchUpstreamSelectorNetworks "fd42:dead:feed:0070:0000:0000:0000:0000/64" "fd42:dead:feed:1000:0:0:0:10"
          && hasRouteAnyNetwork branchUpstreamSelectorNetworks "10.70.10.0/24" "10.50.0.16";
        overlayCoreHasNoHostileTermination =
          !(hasRouteAnyNetwork branchNebulaNetworks "fd42:dead:feed:0070:0000:0000:0000:0000/64" "fd42:dead:feed:1000:0:0:0:5")
          && !(hasRouteAnyNetwork branchCoreNetworks "fd42:dead:feed:0070:0000:0000:0000:0000/64" "fd42:dead:feed:1000:0:0:0:5");
      in
        # s-router-core-isp-b holds 10.10.0.14/31 on its lane toward
        # s-router-upstream-selector, so the remote half of that /31 (10.10.0.0)
        # is the peer and must be reachable on-link in the main table with the
        # peer as next hop. The same holds for the IPv6 /127 half, whose remote
        # half is fd42:dead:beef:1000:0:0:0:f.
        hasOnlinkPeerRoute (branchCoreNetworks."10-upstream".routes or [ ]) "10.10.0.0" "10.10.0.15"
        && hostileDelegatedReturnOnPolicyLane
        && nebHasNoMainGenericDefault
        && nebPolicyTableDefaults
        && hasRouteAnyNetwork branchUpstreamSelectorNetworks "0.0.0.0/0" "10.50.0.6"
        && hasRouteAnyNetwork branchUpstreamSelectorNetworks "::/0" "fd42:dead:feed:1000:0:0:0:6"
    '

echo "PASS transit-endpoint-return-routes"
