#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${repo_root}/tests/lib/test-common.sh"

nix_eval_true_or_fail \
  runtime-origin-preferred-source-routes \
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
                  intent.kind = "runtime-origin-egress";
                  fromInterface = "core-nebula";
                  toInterface = "core-a";
                  sourcePrefixes = [
                    { family = 4; prefix = "10.19.0.8/32"; }
                    { family = 6; prefix = "fd42:dead:beef:1900:0:0:0:8/128"; }
                  ];
                }
              ];
            };
            containerModel = {
              networkBehavior.isUpstreamSelector = true;
              interfaces = {
                core-nebula = {
                  containerInterfaceName = "core-nebula";
                  addresses = [ "10.10.0.17/31" "fd42:dead:beef:1000::11/127" ];
                  interfaceClass.fabricFacing = true;
                  backingRef.lane = {
                    kind = "uplink";
                    uplink = "east-west";
                    uplinks = [ "east-west" ];
                  };
                  routes = [
                    {
                      dst = "0.0.0.0/0";
                      via4 = "10.10.0.16";
                      preferredSource = "10.19.0.8";
                    }
                    {
                      dst = "::/0";
                      via6 = "fd42:dead:beef:1000::10";
                      preferredSource = "fd42:dead:beef:1900:0:0:0:8";
                    }
                  ];
                };
                core-a = {
                  containerInterfaceName = "core-a";
                  addresses = [ "10.10.0.13/31" ];
                  interfaceClass.exitFacing = true;
                  routes = [
                    {
                      dst = "0.0.0.0/0";
                      via4 = "10.10.0.12";
                    }
                  ];
                };
              };
            };
          };
        coreNebulaRoutes = render.networks."10-core-nebula".routes or [ ];
        coreNebulaRules = render.networks."10-core-nebula".routingPolicyRules or [ ];
        hasPreferredRoute =
          builtins.any
            (route:
              (route.Destination or null) == "0.0.0.0/0"
              && (route.Gateway or null) == "10.10.0.16"
              && (route.PreferredSource or null) == "10.19.0.8")
            coreNebulaRoutes;
        hasPreferredRoute6 =
          builtins.any
            (route:
              (route.Destination or null) == "::/0"
              && (route.Gateway or null) == "fd42:dead:beef:1000::10"
              && (route.PreferredSource or null) == "fd42:dead:beef:1900:0:0:0:8")
            coreNebulaRoutes;
        hasScopedRule =
          builtins.any
            (rule:
              (rule.IncomingInterface or null) == "core-nebula"
              && (rule.From or null) == "10.19.0.8/32")
            coreNebulaRules;
        hasBroadRule =
          builtins.any
            (rule:
              (rule.IncomingInterface or null) == "core-nebula"
              && builtins.isInt (rule.Table or null)
              && !(rule ? From))
            coreNebulaRules;
      in
        hasPreferredRoute
        && hasPreferredRoute6
        && hasScopedRule
        && !hasBroadRule
    '

echo "PASS runtime-origin-preferred-source-routes"
