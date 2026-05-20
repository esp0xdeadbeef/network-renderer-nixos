#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${repo_root}/tests/lib/test-common.sh"

nix_eval_true_or_fail \
  policy-downstream-default-route-lane-selection \
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
            forwardingIntent = {
              rules = [
                {
                  action = "accept";
                  fromInterface = "downstream-dmz";
                  toInterface = "up-dmz-wan";
                }
              ];
              policyRelationForwardPairs = [
                {
                  "in" = [ "downstream-dmz" ];
                  "out" = [ "up-client-wan" "up-dmz-wan" ];
                  action = "accept";
                  comment = "allow-hetz-dns-service-to-wan";
                }
              ];
            };
            containerModel = {
              networkBehavior.isPolicy = true;
              policyRoutingSources.downstream-dmz = [ "downstream-dmz" "up-client-wan" "up-dmz-wan" ];
              interfaces = {
                downstream-dmz = {
                  containerInterfaceName = "downstream-dmz";
                  addresses = [ "10.80.0.9/31" ];
                  interfaceClass.fabricFacing = true;
                  routes = [ ];
                };
                up-client-wan = {
                  containerInterfaceName = "up-client-wan";
                  addresses = [ "10.80.0.12/31" ];
                  interfaceClass.exitFacing = true;
                  routes = [
                    {
                      dst = "0.0.0.0/0";
                      via4 = "10.80.0.13";
                    }
                  ];
                };
                up-dmz-wan = {
                  containerInterfaceName = "up-dmz-wan";
                  addresses = [ "10.80.0.16/31" ];
                  interfaceClass.exitFacing = true;
                  routes = [
                    {
                      dst = "0.0.0.0/0";
                      via4 = "10.80.0.17";
                    }
                  ];
                };
              };
            };
          };
        networks = render.networks;
        rules = networks."10-downstream-dmz".routingPolicyRules or [ ];
        tableRules =
          builtins.filter
            (rule:
              (rule.IncomingInterface or null) == "downstream-dmz"
              && builtins.isInt (rule.Table or null)
              && (rule.Table or null) != 254)
            rules;
        table = if tableRules == [ ] then null else (builtins.head tableRules).Table;
        wanRoutes = networks."10-up-dmz-wan".routes or [ ];
        clientWanRoutes = networks."10-up-client-wan".routes or [ ];
        hasDmzWanDefault =
          table != null
          && builtins.any
            (route:
              (route.Destination or null) == "0.0.0.0/0"
              && (route.Gateway or null) == "10.80.0.17"
              && (route.Table or null) == table)
            wanRoutes;
        hasClientWanDefault =
          table != null
          && builtins.any
            (route:
              (route.Destination or null) == "0.0.0.0/0"
              && (route.Gateway or null) == "10.80.0.13"
              && (route.Table or null) == table)
            clientWanRoutes;
      in
        hasDmzWanDefault && !hasClientWanDefault
    '

echo "PASS policy-downstream-default-route-lane-selection"
