#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

REPO_ROOT="${repo_root}" nix eval \
  --extra-experimental-features 'nix-command flakes' \
  --impure \
  --expr '
    let
      repoRoot = builtins.getEnv "REPO_ROOT";
      flake = builtins.getFlake ("path:" + repoRoot);
      lib = flake.inputs.nixpkgs.lib;
      render =
        model:
        import (repoRoot + "/s88/ControlModule/render/container-networks.nix") {
          inherit lib;
          containerModel = model;
          uplinks = { };
          wanUplinkName = null;
        };
      default4 = gateway: {
        dst = "0.0.0.0/0";
        via4 = gateway;
      };
      default6 = gateway: {
        dst = "::/0";
        via6 = gateway;
      };
      selectorRender =
        render {
          interfaces = {
            access-branch = {
              containerInterfaceName = "access-branch";
              addresses = [ "10.50.0.1/31" "fd42:dead:feed:1000::1/127" ];
            };
            access-hostile = {
              containerInterfaceName = "access-hostile";
              addresses = [ "10.50.0.3/31" "fd42:dead:feed:1000::3/127" ];
            };
            policy-branch = {
              containerInterfaceName = "policy-branch";
              addresses = [ "10.50.0.6/31" "fd42:dead:feed:1000::6/127" ];
              routes = [
                (default4 "10.50.0.7")
                (default6 "fd42:dead:feed:1000::7")
              ];
            };
            policy-hostile = {
              containerInterfaceName = "policy-hostile";
              addresses = [ "10.50.0.8/31" "fd42:dead:feed:1000::8/127" ];
              routes = [
                (default4 "10.50.0.9")
                (default6 "fd42:dead:feed:1000::9")
              ];
            };
          };
        };
      policyRender =
        render {
          interfaces = {
            downstream-branch = {
              containerInterfaceName = "downstream-branch";
              addresses = [ "10.50.0.7/31" "fd42:dead:feed:1000::7/127" ];
            };
            downstream-hostile = {
              containerInterfaceName = "downstream-hostile";
              addresses = [ "10.50.0.9/31" "fd42:dead:feed:1000::9/127" ];
            };
            upstream-branch = {
              containerInterfaceName = "upstream-branch";
              addresses = [ "10.51.0.2/31" "fd42:dead:feed:1100::2/127" ];
              routes = [
                (default4 "10.51.0.3")
                (default6 "fd42:dead:feed:1100::3")
              ];
            };
            up-hostile = {
              containerInterfaceName = "up-hostile";
              addresses = [ "10.52.0.2/31" "fd42:dead:feed:1200::2/127" ];
              routes = [
                (default4 "10.52.0.3")
                (default6 "fd42:dead:feed:1200::3")
              ];
            };
          };
        };
      upstreamSelectorRender =
        render {
          interfaces = {
            core-a = {
              containerInterfaceName = "core-a";
              addresses = [ "10.10.0.11/31" "fd42:dead:beef:1000::b/127" ];
              routes = [
                (default4 "10.10.0.10")
                (default6 "fd42:dead:beef:1000::a")
              ];
            };
            pol-mgmt-a = {
              containerInterfaceName = "pol-mgmt-a";
              addresses = [ "10.10.0.45/31" "fd42:dead:beef:1000::2d/127" ];
            };
            policy-mgmt-wan = {
              containerInterfaceName = "policy-mgmt-wan";
              addresses = [ "10.10.0.47/31" "fd42:dead:beef:1000::2f/127" ];
            };
          };
        };
      upstreamSelectorLongNameRender =
        render {
          interfaces = {
            core = {
              containerInterfaceName = "core";
              addresses = [ "10.80.0.11/31" "fd42:dead:cafe:1000::b/127" ];
              routes = [
                (default4 "10.80.0.10")
                (default6 "fd42:dead:cafe:1000::a")
              ];
            };
            policy-mgmt-wan = {
              containerInterfaceName = "policy-mgmt-wan";
              addresses = [ "10.80.0.29/31" "fd42:dead:cafe:1000::1d/127" ];
            };
          };
        };
      selectorPolicyBranch = selectorRender.networks."10-policy-branch".routes or [ ];
      selectorPolicyHostile = selectorRender.networks."10-policy-hostile".routes or [ ];
      selectorBranchRules = selectorRender.networks."10-access-branch".routingPolicyRules or [ ];
      selectorHostileRules = selectorRender.networks."10-access-hostile".routingPolicyRules or [ ];
      policyUpstreamBranch = policyRender.networks."10-upstream-branch".routes or [ ];
      policyUpHostile = policyRender.networks."10-up-hostile".routes or [ ];
      policyBranchRules = policyRender.networks."10-downstream-branch".routingPolicyRules or [ ];
      policyHostileRules = policyRender.networks."10-downstream-hostile".routingPolicyRules or [ ];
      upstreamCoreRoutes = upstreamSelectorRender.networks."10-core-a".routes or [ ];
      upstreamPolicyRoutes = upstreamSelectorRender.networks."10-pol-mgmt-a".routes or [ ];
      upstreamPolicyRules = upstreamSelectorRender.networks."10-pol-mgmt-a".routingPolicyRules or [ ];
      upstreamLongPolicyRules =
        upstreamSelectorLongNameRender.networks."10-policy-mgmt-wan".routingPolicyRules or [ ];
      upstreamLongCoreRoutes =
        upstreamSelectorLongNameRender.networks."10-core".routes or [ ];
      routesAllHaveTable =
        expectedTable: routes:
        builtins.length routes > 0
        && builtins.all (route: (route.Table or null) == expectedTable) routes;
      hasIngressRule =
        expectedIf: expectedTable: rules:
        builtins.any (
          rule:
          (rule.IncomingInterface or null) == expectedIf
          && (rule.Table or null) == expectedTable
        ) rules;
    in
    routesAllHaveTable 2000 selectorPolicyBranch
    && routesAllHaveTable 2001 selectorPolicyHostile
    && hasIngressRule "access-branch" 2000 selectorBranchRules
    && hasIngressRule "access-hostile" 2001 selectorHostileRules
    && routesAllHaveTable 2000 policyUpstreamBranch
    && routesAllHaveTable 2001 policyUpHostile
    && hasIngressRule "downstream-branch" 2000 policyBranchRules
    && hasIngressRule "downstream-hostile" 2001 policyHostileRules
    && routesAllHaveTable 2000 upstreamCoreRoutes
    && routesAllHaveTable 2001 upstreamPolicyRoutes
    && hasIngressRule "pol-mgmt-a" 2001 upstreamPolicyRules
    && routesAllHaveTable 2001 upstreamLongCoreRoutes
    && hasIngressRule "policy-mgmt-wan" 2001 upstreamLongPolicyRules
    && hasIngressRule "policy-mgmt-wan" 12001 upstreamLongPolicyRules
  ' >/dev/null || {
    echo "FAIL lane-route-scoping" >&2
    exit 1
  }

echo "PASS lane-route-scoping"
