#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${repo_root}/tests/lib/test-common.sh"

nix_eval_true_or_fail \
  downstream-selector-local-forward-policy-sources \
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
              {
                action = "accept";
                fromInterface = "access-client";
                toInterface = "policy-client";
                sourcePrefixes = [
                  {
                    family = 4;
                    prefix = "10.19.0.8/32";
                  }
                ];
              }
              { action = "accept"; fromInterface = "access-dmz"; toInterface = "policy-dmz"; }
              { action = "accept"; fromInterface = "policy-client"; toInterface = "access-client"; }
              { action = "accept"; fromInterface = "policy-dmz"; toInterface = "access-dmz"; }
              { action = "accept"; fromInterface = "access-client"; toInterface = "access-dmz"; }
            ];
            containerModel = {
              networkBehavior = {
                isSelector = true;
                isDownstreamSelector = true;
              };
              policyRoutingSources = {
                access-client = [ "access-client" "policy-client" ];
                access-dmz = [ "access-dmz" "policy-dmz" ];
              };
              interfaces = {
                p2p-access-client = {
                  containerInterfaceName = "access-client";
                  interfaceClass.edgeFacing = true;
                  addresses = [ "10.80.0.1/31" ];
                  routes = [
                    {
                      dst = "10.90.20.0/24";
                      via4 = "10.80.0.0";
                    }
                  ];
                };
                p2p-access-dmz = {
                  containerInterfaceName = "access-dmz";
                  interfaceClass.edgeFacing = true;
                  addresses = [ "10.80.0.3/31" ];
                  routes = [
                    {
                      dst = "10.90.10.0/24";
                      via4 = "10.80.0.2";
                    }
                  ];
                };
                p2p-policy-client = {
                  containerInterfaceName = "policy-client";
                  interfaceClass.fabricFacing = true;
                  addresses = [ "10.80.0.7/31" ];
                  routes = [
                    {
                      dst = "0.0.0.0/0";
                      via4 = "10.80.0.6";
                    }
                  ];
                };
                p2p-policy-dmz = {
                  containerInterfaceName = "policy-dmz";
                  interfaceClass.fabricFacing = true;
                  addresses = [ "10.80.0.9/31" ];
                  routes = [
                    {
                      dst = "0.0.0.0/0";
                      via4 = "10.80.0.8";
                    }
                  ];
                };
              };
            };
          };
        networks = render.networks;
        rules = networks."10-access-client".routingPolicyRules or [ ];
        policyRules = networks."10-policy-client".routingPolicyRules or [ ];
        allRules = rules ++ policyRules;
        policyClientRoutes = networks."10-policy-client".routes or [ ];
        tableRules =
          builtins.filter
            (rule:
              (rule.IncomingInterface or null) == "access-client"
              && builtins.isInt (rule.Table or null)
              && (rule.Table or null) != 254)
            rules;
        table = if tableRules == [ ] then null else (builtins.head tableRules).Table;
        accessDmzRoutes = networks."10-access-dmz".routes or [ ];
        hasDmzRouteInClientTable =
          table != null
          && builtins.any
            (route:
              (route.Destination or null) == "10.90.10.0/24"
              && (route.Gateway or null) == "10.80.0.2"
              && (route.Table or null) == table)
            accessDmzRoutes;
        policyClientDefaultTables =
          map
            (route: route.Table)
            (builtins.filter
              (route:
                (route.Destination or null) == "0.0.0.0/0"
                && builtins.isInt (route.Table or null))
              policyClientRoutes);
        policyClientDefaultTable =
          if policyClientDefaultTables == [ ] then null else builtins.head policyClientDefaultTables;
        hasRuntimeOriginPolicyRule =
          builtins.any
            (rule:
              (rule.IncomingInterface or null) == "access-client"
              && (rule.From or null) == "10.19.0.8/32"
              && (rule.Table or null) == policyClientDefaultTable
              && (rule.Priority or 99999) < 10000)
            allRules;
        wrongRuntimeOriginPolicyRules =
          builtins.filter
            (rule:
              (rule.IncomingInterface or null) == "access-client"
              && (rule.From or null) == "10.19.0.8/32"
              && builtins.isInt (rule.Table or null)
              && (rule.Table or null) != 254
              && (rule.Table or null) != policyClientDefaultTable)
            allRules;
      in
        if !(hasDmzRouteInClientTable) then
          throw ("downstream selector local forward table lost explicit accepted target: " + builtins.toJSON {
            inherit table rules accessDmzRoutes;
          })
        else if !(hasRuntimeOriginPolicyRule) then
          throw ("downstream selector policy table did not select explicit runtime-origin source ingress: " + builtins.toJSON {
            inherit allRules policyClientDefaultTable policyClientRoutes;
          })
        else if wrongRuntimeOriginPolicyRules != [ ] then
          throw ("downstream selector emitted runtime-origin source ingress against the wrong table: " + builtins.toJSON {
            inherit wrongRuntimeOriginPolicyRules policyClientDefaultTable;
          })
        else
          true
    '

echo "PASS downstream-selector-local-forward-policy-sources"
