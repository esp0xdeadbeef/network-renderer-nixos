#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${repo_root}/tests/lib/test-common.sh"

nix_eval_true_or_fail \
  traffic-type-forward-rules-do-not-steal-policy-routes \
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
              {
                action = "accept";
                fromInterface = "pol-client-b";
                toInterface = "core-a";
                trafficType = "nebula";
              }
              {
                action = "accept";
                fromInterface = "pol-client-b";
                toInterface = "core-b";
              }
              {
                action = "accept";
                fromInterface = "core-b";
                toInterface = "pol-client-b";
              }
            ];
            containerModel = {
              networkBehavior.isUpstreamSelector = true;
              interfaces = {
                core-a = {
                  containerInterfaceName = "core-a";
                  addresses = [ "10.10.0.12/31" ];
                  interfaceClass.coreFacing = true;
                  backingRef.lane.uplink = "isp-a";
                  routes = [ ];
                };
                core-b = {
                  containerInterfaceName = "core-b";
                  addresses = [ "10.10.0.14/31" ];
                  interfaceClass.coreFacing = true;
                  backingRef.lane.uplink = "isp-b";
                  routes = [ ];
                };
                pol-client-b = {
                  containerInterfaceName = "pol-client-b";
                  addresses = [ "10.10.0.37/31" ];
                  interfaceClass.exitFacing = true;
                  backingRef.lane = {
                    access = "router-access-client";
                    uplink = "isp-b";
                    uplinks = [ "isp-b" ];
                  };
                  routes = [
                    {
                      dst = "0.0.0.0/0";
                      via4 = "10.10.0.14";
                      policyOnly = true;
                      reason = "policy-derived-default";
                      lane.access = "router-access-client";
                      lane.uplink = "isp-b";
                    }
                  ];
                };
              };
            };
          };
        coreARules = render.networks."10-core-a".routingPolicyRules or [ ];
        coreBRules = render.networks."10-core-b".routingPolicyRules or [ ];
        hasUnscopedIngressRule = rules: iface:
          builtins.any (
            rule:
              (rule.IncomingInterface or null) == iface
              && (rule.Table or null) != 254
              && !(rule ? From)
              && !(rule ? To)
          ) rules;
      in
        if hasUnscopedIngressRule coreARules "pol-client-b" then
          throw "trafficType-only pol-client-b -> core-a rule stole all pol-client-b traffic into core-a table"
        else if !(hasUnscopedIngressRule coreBRules "pol-client-b") then
          throw "broad pol-client-b -> core-b rule did not create the expected client-b policy route"
        else
          true
    '

echo "PASS traffic-type-forward-rules-do-not-steal-policy-routes"
