#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${repo_root}/tests/lib/test-common.sh"

nix_eval_true_or_fail \
  access-return-connected-routes \
  env REPO_ROOT="${repo_root}" \
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
              { action = "accept"; fromInterface = "tenant-client"; toInterface = "transit"; }
              { action = "accept"; fromInterface = "transit"; toInterface = "tenant-client"; }
            ];
            containerModel = {
              site.tenantPrefixOwners."4|10.20.20.0/24".owner = "router-access-client";
              interfaces = {
                tenant-client = {
                  containerInterfaceName = "tenant-client";
                  addresses = [ "10.20.20.1/24" "fd42:dead:beef:20:0:0:0:1/64" ];
                  interfaceClass.edgeFacing = true;
                  backingRef.lane.access = "router-access-client";
                  routes = [ ];
                };
                transit = {
                  containerInterfaceName = "transit";
                  addresses = [ "10.10.0.4/31" "fd42:dead:beef:1000::4/127" ];
                  interfaceClass.fabricFacing = true;
                  backingRef.lane.access = "router-access-client";
                  routes = [
                    {
                      dst = "0.0.0.0/0";
                      via4 = "10.10.0.5";
                    }
                    {
                      dst = "::/0";
                      via6 = "fd42:dead:beef:1000::5";
                      family = 6;
                    }
                  ];
                };
              };
            };
          };
        networks = render.networks;
        transitRules =
          builtins.filter
            (rule:
              (rule.IncomingInterface or null) == "transit"
              && builtins.isInt (rule.Table or null)
              && (rule.Table or null) != 254)
            (networks."10-transit".routingPolicyRules or [ ]);
        transitTable =
          if transitRules == [ ] then null else (builtins.head transitRules).Table;
        tenantRoutes = networks."10-tenant-client".routes or [ ];
        hasTenant4 =
          transitTable != null
          && builtins.any
            (route:
              (route.Destination or null) == "10.20.20.0/24"
              && (route.Table or null) == transitTable
              && !(route ? Gateway))
            tenantRoutes;
        hasTenant6 =
          transitTable != null
          && builtins.any
            (route:
              (route.Destination or null) == "fd42:dead:beef:20::/64"
              && (route.Table or null) == transitTable
              && !(route ? Gateway))
            tenantRoutes;
      in
        if hasTenant4 && hasTenant6 then true else throw ("access return table lacks connected tenant routes: " + builtins.toJSON {
          inherit transitTable transitRules tenantRoutes;
        })
    '

echo "PASS access-return-connected-routes"
