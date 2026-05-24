#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${repo_root}/tests/lib/test-common.sh"

nix_eval_true_or_fail \
  policy-routing-source-interface-rules \
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
              { action = "accept"; fromInterface = "policy-client"; toInterface = "core-b"; }
              { action = "accept"; fromInterface = "core-b"; toInterface = "policy-client"; }
            ];
            containerModel = {
              networkBehavior.isUpstreamSelector = true;
              policyRoutingSources.policy-client = [ "policy-client" "core-b" ];
              interfaces = {
                core-b = {
                  containerInterfaceName = "core-b";
                  addresses = [ "10.10.0.38/31" ];
                  interfaceClass.coreFacing = true;
                  backingRef.lane = {
                    uplink = "isp-b";
                    uplinks = [ "isp-b" ];
                  };
                  routes = [ ];
                };
                policy-client = {
                  containerInterfaceName = "policy-client";
                  addresses = [ "10.10.0.39/31" ];
                  interfaceClass.exitFacing = true;
                  backingRef.lane = {
                    access = "router-access-client";
                    uplink = "isp-b";
                    uplinks = [ "isp-b" ];
                  };
                  routes = [
                    {
                      dst = "0.0.0.0/0";
                      via4 = "10.10.0.38";
                      policyOnly = true;
                      reason = "policy-derived-default";
                      lane.access = "router-access-client";
                      lane.uplink = "isp-b";
                    }
                    {
                      dst = "10.20.20.0/24";
                      via4 = "10.10.0.38";
                      policyOnly = true;
                      reason = "policy-table-internal-reachability";
                      lane.access = "router-access-client";
                      lane.uplink = "isp-b";
                    }
                  ];
                };
              };
            };
          };
        rules = render.networks."10-policy-client".routingPolicyRules or [ ];
        hasRule = iface:
          builtins.any (
            rule:
              (rule.IncomingInterface or null) == iface
              && (rule.Table or null) != 254
              && (rule.Priority or null) < 10000
          ) rules;
        mainBeforeTable =
          builtins.any (
            rule:
              (rule.IncomingInterface or null) == "core-b"
              && (rule.Table or null) == 254
              && (rule.Priority or 99999) < 10000
          ) rules;
      in
        if !(hasRule "policy-client") then
          throw "policy-client ingress did not select its own lane table"
        else if !(hasRule "core-b") then
          throw "core-b return ingress did not select the policy-client lane table"
        else if mainBeforeTable then
          throw "main table lookup still precedes lane table lookup for core-b return ingress"
        else
          true
    '

echo "PASS policy-routing-source-interface-rules"
