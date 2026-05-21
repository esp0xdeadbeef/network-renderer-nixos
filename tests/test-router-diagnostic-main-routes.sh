#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${repo_root}/tests/lib/test-common.sh"

nix_eval_true_or_fail \
  router-diagnostic-main-routes \
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
              { action = "accept"; fromInterface = "access-hostile"; toInterface = "policy-hostile"; }
              { action = "accept"; fromInterface = "policy-hostile"; toInterface = "access-hostile"; }
            ];
            containerModel = {
              networkBehavior = {
                isSelector = true;
                isDownstreamSelector = true;
              };
              site.tenantPrefixOwners."4|10.20.70.0/24".owner = "router-access-hostile";
              interfaces = {
                access-hostile = {
                  containerInterfaceName = "access-hostile";
                  interfaceClass.edgeFacing = true;
                  backingRef.lane.access = "router-access-hostile";
                  addresses = [ "10.10.0.7/31" ];
                  routes = [ ];
                };
                policy-hostile = {
                  containerInterfaceName = "policy-hostile";
                  interfaceClass.fabricFacing = true;
                  backingRef.lane.access = "router-access-hostile";
                  addresses = [ "10.10.0.24/31" ];
                  routes = [
                    {
                      dst = "0.0.0.0/0";
                      via4 = "10.10.0.25";
                      policyOnly = true;
                      reason = "policy-derived-default";
                      lane.access = "router-access-hostile";
                      lane.uplink = "east-west";
                    }
                    {
                      dst = "10.20.70.0/24";
                      via4 = "10.10.0.6";
                      intent.kind = "internal-reachability";
                    }
                  ];
                };
              };
            };
          };
        accessRoutes = render.networks."10-access-hostile".routes or [ ];
        policyRoutes = render.networks."10-policy-hostile".routes or [ ];
        hasMainReturn =
          builtins.any
            (route:
              (route.Destination or null) == "10.20.70.0/24"
              && (route.Gateway or null) == "10.10.0.6"
              && !(route ? Table))
            accessRoutes;
        hasPolicyDefault =
          builtins.any
            (route:
              (route.Destination or null) == "0.0.0.0/0"
              && (route.Gateway or null) == "10.10.0.25"
              && (route.Table or null) != null)
            policyRoutes;
        leakedMainDefault =
          builtins.any
            (route:
              (route.Destination or null) == "0.0.0.0/0"
              && !(route ? Table))
            policyRoutes;
      in
        if !(hasMainReturn && hasPolicyDefault && !leakedMainDefault) then
          throw ("router diagnostic main route projection failed: " + builtins.toJSON {
            inherit accessRoutes policyRoutes;
          })
        else true
    '

echo "PASS router-diagnostic-main-routes"
