#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${repo_root}/tests/lib/test-common.sh"

nix_eval_true_or_fail "hostile-dns-east-west" env REPO_ROOT="${repo_root}" \
  nix eval \
    --extra-experimental-features 'nix-command flakes' \
    --impure --expr '
      let
        repoRoot = builtins.getEnv "REPO_ROOT";
        flake = builtins.getFlake ("path:" + repoRoot);
        lib = flake.inputs.nixpkgs.lib;
        render =
          import (repoRoot + "/s88/ControlModule/render/container-networks.nix") {
            inherit lib;
            uplinks = { };
            wanUplinkName = null;
            forwardingIntent.rules = [
              {
                action = "accept";
                fromInterface = "downstr-hostile";
                toInterface = "up-hostile-ew";
              }
            ];
            containerModel = {
              networkBehavior.isPolicy = true;
              site.tenantPrefixOwners = {
                "4|10.20.70.0/24".owner = "router-access-hostile";
                "6|2a01:4f9:c01f:8034::/64".owner = "router-access-hostile";
              };
              interfaces = {
                downstr-hostile = {
                  containerInterfaceName = "downstr-hostile";
                  addresses = [
                    "10.50.0.16/31"
                    "fd42:dead:feed:1000::10/127"
                  ];
                  interfaceClass.fabricFacing = true;
                  backingRef.lane.access = "router-access-hostile";
                };
                up-hostile-ew = {
                  containerInterfaceName = "up-hostile-ew";
                  addresses = [
                    "10.50.0.17/31"
                    "fd42:dead:feed:1000::11/127"
                  ];
                  interfaceClass.exitFacing = true;
                  backingRef.lane = {
                    access = "router-access-hostile";
                    uplink = "east-west";
                    uplinks = [ "east-west" ];
                  };
                  routes = [
                    {
                      dst = "10.20.10.0/24";
                      via4 = "10.50.0.16";
                      policyOnly = true;
                      lane.access = "router-access-hostile";
                      lane.uplink = "east-west";
                    }
                    {
                      dst = "10.90.10.0/24";
                      via4 = "10.50.0.16";
                      policyOnly = true;
                      lane.access = "router-access-hostile";
                      lane.uplink = "east-west";
                    }
                    {
                      dst = "fd42:dead:beef:0010:0000:0000:0000:0000/64";
                      via6 = "fd42:dead:feed:1000:0:0:0:10";
                      policyOnly = true;
                      lane.access = "router-access-hostile";
                      lane.uplink = "east-west";
                    }
                    {
                      dst = "::/0";
                      via6 = "fd42:dead:feed:1000:0:0:0:10";
                      policyOnly = true;
                      lane.access = "router-access-hostile";
                      lane.uplink = "east-west";
                    }
                  ];
                };
              };
            };
          };
        networks = render.networks;
        up = networks."10-up-hostile-ew";
        down = networks."10-downstr-hostile";
        upRoutes = up.routes or [ ];
        downRoutes = down.routes or [ ];
        upRules = up.routingPolicyRules or [ ];
        hasRoute = routes: destination: gateway: table:
          builtins.any
            (route:
              (route.Destination or null) == destination
              && (route.Gateway or null) == gateway
              && (route.Table or null) == table)
            routes;
        hasRule = incomingInterface: table:
          builtins.any
            (rule:
              (rule.IncomingInterface or null) == incomingInterface
              && (rule.Table or null) == table)
            upRules;
        isDefault =
          route:
          (route.Destination or null) == null
          || (route.Destination or null) == "0.0.0.0/0"
          || (route.Destination or null) == "::/0"
          || (route.Destination or null) == "0000:0000:0000:0000:0000:0000:0000:0000/0";
        hasDefaultVia = routes: gateway: table:
          builtins.any
            (route:
              isDefault route
              && (route.Gateway or null) == gateway
              && (route.Table or null) == table)
            routes;
      in
        hasRoute upRoutes "10.20.10.0/24" "10.50.0.16" 2001
        && hasRoute upRoutes "fd42:dead:beef:0010:0000:0000:0000:0000/64" "fd42:dead:feed:1000:0:0:0:10" 2001
        && hasRoute upRoutes "10.90.10.0/24" "10.50.0.16" 2001
        && !(hasRoute downRoutes "10.90.10.0/24" "10.50.0.16" 2001)
        && hasDefaultVia upRoutes "fd42:dead:feed:1000:0:0:0:10" 2001
        && !(hasDefaultVia downRoutes "fd42:dead:feed:1000:0:0:0:10" 2001)
        && hasRule "downstr-hostile" 2001
    '

echo "PASS hostile-dns-east-west"
