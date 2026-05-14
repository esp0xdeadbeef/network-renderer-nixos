#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${repo_root}/tests/lib/test-common.sh"

nix_eval_true_or_fail \
  policy-routing-explicit-forward-pairs \
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
              policyRelationForwardPairs = [
                {
                  action = "accept";
                  "in" = [ "up-cli-ew" ];
                  "out" = [ "up-mgt-ew" ];
                  comment = "allow-east-west-to-nixos-mgmt-dns";
                }
              ];
            };
            containerModel = {
              interfaces = {
                downstream-mgmt = {
                  containerInterfaceName = "downstream-mgmt";
                  addresses = [ "10.10.0.27/31" ];
                  backingRef.lane = {
                    kind = "access";
                    access = "s-router-access-mgmt";
                    uplink = "east-west";
                    uplinks = [ "east-west" ];
                  };
                  routes = [
                    {
                      dst = "10.20.10.0/24";
                      via4 = "10.10.0.26";
                    }
                  ];
                };
                up-cli-ew = {
                  containerInterfaceName = "up-cli-ew";
                  addresses = [ "10.10.0.37/31" ];
                  backingRef.lane = {
                    kind = "access-uplink";
                    access = "s-router-access-client";
                    uplink = "east-west";
                    uplinks = [ "east-west" ];
                  };
                  routes = [ ];
                };
                up-mgt-ew = {
                  containerInterfaceName = "up-mgt-ew";
                  addresses = [ "10.10.0.49/31" ];
                  backingRef.lane = {
                    kind = "access-uplink";
                    access = "s-router-access-mgmt";
                    uplink = "east-west";
                    uplinks = [ "east-west" ];
                  };
                  routes = [
                    {
                      dst = "10.20.10.0/24";
                      via4 = "10.10.0.26";
                    }
                  ];
                };
              };
            };
          };
        networks = render.networks;
        rules = networks."10-up-cli-ew".routingPolicyRules or [ ];
        tableRules =
          builtins.filter
            (rule:
              (rule.IncomingInterface or null) == "up-cli-ew"
              && builtins.isInt (rule.Table or null)
              && (rule.Table or null) != 254)
            rules;
        table = if tableRules == [ ] then null else (builtins.head tableRules).Table;
        downstreamRoutes = networks."10-downstream-mgmt".routes or [ ];
        hasMgmtDnsRoute =
          table != null
          && builtins.any
            (route:
              (route.Destination or null) == "10.20.10.0/24"
              && (route.Gateway or null) == "10.10.0.26"
              && (route.Table or null) == table)
            downstreamRoutes;
      in
        hasMgmtDnsRoute
    '

echo "PASS policy-routing-explicit-forward-pairs"
