#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${repo_root}/tests/lib/test-common.sh"

nix_eval_true_or_fail \
  upstream-runtime-origin-source-lane-rules \
  env REPO_ROOT="${repo_root}" \
    nix eval \
    --extra-experimental-features 'nix-command flakes' \
    --impure --expr '
      let
        repoRoot = builtins.getEnv "REPO_ROOT";
        flake = builtins.getFlake ("path:" + repoRoot);
        lib = flake.inputs.nixpkgs.lib;
        runtimeSource = {
          family = 4;
          prefix = "10.19.0.8/32";
        };
        render =
          import (repoRoot + "/s88/ControlModule/render/container-networks.nix") {
            inherit lib;
            uplinks = { };
            wanUplinkName = null;
            forwardingIntent.rules = [
              {
                action = "accept";
                fromInterface = "pol-client-a";
                toInterface = "core-a";
                sourcePrefixes = [ runtimeSource ];
              }
              {
                action = "accept";
                fromInterface = "pol-client-b";
                toInterface = "core-b";
                sourcePrefixes = [ runtimeSource ];
              }
            ];
            containerModel = {
              networkBehavior.isUpstreamSelector = true;
              policyRoutingSources = {
                core-a = [ "pol-client-a" "pol-client-b" "core-a" ];
                core-b = [ "pol-client-a" "pol-client-b" "core-b" ];
              };
              interfaces = {
                core-a = {
                  containerInterfaceName = "core-a";
                  addresses = [ "10.10.0.14/31" ];
                  interfaceClass.coreFacing = true;
                  routes = [ ];
                  backingRef.lane.uplink = "isp-a";
                };
                core-b = {
                  containerInterfaceName = "core-b";
                  addresses = [ "10.10.0.16/31" ];
                  interfaceClass.coreFacing = true;
                  routes = [ ];
                  backingRef.lane.uplink = "isp-b";
                };
                pol-client-a = {
                  containerInterfaceName = "pol-client-a";
                  addresses = [ "10.10.0.37/31" ];
                  interfaceClass.exitFacing = true;
                  backingRef.lane = {
                    access = "router-access-client";
                    uplink = "isp-a";
                    uplinks = [ "isp-a" ];
                  };
                  routes = [ ];
                };
                pol-client-b = {
                  containerInterfaceName = "pol-client-b";
                  addresses = [ "10.10.0.39/31" ];
                  interfaceClass.exitFacing = true;
                  backingRef.lane = {
                    access = "router-access-client";
                    uplink = "isp-b";
                    uplinks = [ "isp-b" ];
                  };
                  routes = [ ];
                };
              };
            };
          };
        coreARules = render.networks."10-core-a".routingPolicyRules or [ ];
        coreBRules = render.networks."10-core-b".routingPolicyRules or [ ];
        hasRuntimeRule = rules: incomingInterface:
          builtins.any (
            rule:
              (rule.From or null) == runtimeSource.prefix
              && (rule.IncomingInterface or null) == incomingInterface
              && (rule.Table or null) != 254
          ) rules;
      in
        if !(hasRuntimeRule coreARules "pol-client-a") then
          throw "core-a table is missing the explicit pol-client-a runtime-origin rule"
        else if hasRuntimeRule coreARules "pol-client-b" then
          throw "core-a table incorrectly captures pol-client-b runtime-origin traffic"
        else if !(hasRuntimeRule coreBRules "pol-client-b") then
          throw "core-b table is missing the explicit pol-client-b runtime-origin rule"
        else if hasRuntimeRule coreBRules "pol-client-a" then
          throw "core-b table incorrectly captures pol-client-a runtime-origin traffic"
        else
          true
    '

echo "PASS upstream-runtime-origin-source-lane-rules"
