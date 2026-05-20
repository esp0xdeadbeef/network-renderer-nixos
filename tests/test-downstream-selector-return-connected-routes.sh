#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${repo_root}/tests/lib/test-common.sh"

nix_eval_true_or_fail \
  downstream-selector-return-connected-routes \
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
              { action = "accept"; fromInterface = "access-client"; toInterface = "policy-client"; }
              { action = "accept"; fromInterface = "policy-client"; toInterface = "access-client"; }
            ];
            containerModel = {
              networkBehavior = {
                isSelector = true;
                isDownstreamSelector = true;
              };
              interfaces = {
                access-client = {
                  containerInterfaceName = "access-client";
                  interfaceClass.edgeFacing = true;
                  addresses = [ "10.10.0.3/31" ];
                  routes = [ ];
                };
                policy-client = {
                  containerInterfaceName = "policy-client";
                  interfaceClass.fabricFacing = true;
                  addresses = [ "10.10.0.20/31" ];
                  routes = [
                    {
                      dst = "0.0.0.0/0";
                      via4 = "10.10.0.21";
                    }
                  ];
                };
              };
            };
          };
        networks = render.networks;
        rules = networks."10-policy-client".routingPolicyRules or [ ];
        tableRules =
          builtins.filter
            (rule:
              (rule.IncomingInterface or null) == "policy-client"
              && builtins.isInt (rule.Table or null)
              && (rule.Table or null) != 254)
            rules;
        table = if tableRules == [ ] then null else (builtins.head tableRules).Table;
        accessRoutes = networks."10-access-client".routes or [ ];
        hasConnectedReturn =
          table != null
          && builtins.any
            (route:
              (route.Destination or null) == "10.10.0.2/31"
              && (route.Scope or null) == "link"
              && (route.Table or null) == table)
            accessRoutes;
      in
        if hasConnectedReturn then true else throw ("downstream selector return table lacks connected access p2p route: " + builtins.toJSON {
          inherit table accessRoutes rules;
        })
    '

echo "PASS downstream-selector-return-connected-routes"
