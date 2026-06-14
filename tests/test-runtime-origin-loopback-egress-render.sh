#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${repo_root}/tests/lib/test-common.sh"

example_root="$(flake_input_path network-labs)/examples/s-router-overlay-dns-lane-policy"

nix_eval_true_or_fail "runtime-origin-loopback-egress-render" env \
  REPO_ROOT="${repo_root}" \
  INTENT_PATH="${example_root}/intent.nix" \
  INVENTORY_PATH="${example_root}/inventory-nixos.nix" \
  nix eval \
    --extra-experimental-features 'nix-command flakes' \
    --impure --expr '
      let
        repoRoot = "path:" + builtins.getEnv "REPO_ROOT";
        flake = builtins.getFlake repoRoot;
        system = "x86_64-linux";
        built = import (builtins.getEnv "REPO_ROOT" + "/tests/nix/build-host-from-paths.nix") {
          selector = "s-router-test";
          intentPath = builtins.getEnv "INTENT_PATH";
          inventoryPath = builtins.getEnv "INVENTORY_PATH";
          inherit system;
        };
        nixpkgsLib = flake.inputs.nixpkgs.lib;
        evalContainer = name:
          (nixpkgsLib.nixosSystem {
            inherit system;
            modules = [ built.renderedHost.containers.${name}.config ];
          }).config;
        coreNebula = evalContainer "s-router-core-nebula";
        upstream = evalContainer "s-router-upstream-selector";
        policy = evalContainer "s-router-policy-only";
        coreNebulaRoutes = coreNebula.systemd.network.networks."10-upstream".routes or [ ];
        upstreamRules =
          nixpkgsLib.concatLists (
            nixpkgsLib.mapAttrsToList (_networkName: network: network.routingPolicyRules or [ ])
              upstream.systemd.network.networks
          );
        upstreamRoutes = upstream.systemd.network.networks."10-core-a".routes or [ ];
        policyDownstreamClientRules =
          nixpkgsLib.concatLists (
            nixpkgsLib.mapAttrsToList (_networkName: network: network.routingPolicyRules or [ ])
              policy.systemd.network.networks
          );
        policyDownstreamClientRoutes = policy.systemd.network.networks."10-down-client".routes or [ ];
        policyRoutes =
          nixpkgsLib.concatLists (
            nixpkgsLib.mapAttrsToList (_networkName: network: network.routes or [ ])
              policy.systemd.network.networks
          );
        policyUpClientARoutes = policy.systemd.network.networks."10-up-client-a".routes or [ ];
        policyUpClientBRoutes = policy.systemd.network.networks."10-up-client-b".routes or [ ];
        policyNetworks = policy.systemd.network.networks;
        runtimeOriginHasAccessOrigin =
          let
            targets =
              nixpkgsLib.concatLists (
                nixpkgsLib.mapAttrsToList
                  (_enterpriseName: enterprise:
                    nixpkgsLib.concatLists (
                      nixpkgsLib.mapAttrsToList
                        (_siteName: site: builtins.attrValues (site.runtimeTargets or { }))
                        enterprise
                    ))
                  built.controlPlaneOut.control_plane_model.data
              );
          in
          builtins.any
            (target:
              builtins.any
                (prefix:
                  builtins.isAttrs (prefix.origin or null)
                  && builtins.isList (prefix.origin.accesses or null)
                  && prefix.origin.accesses != [ ])
                ((target.runtimeOriginEgress or { }).sourcePrefixes or [ ]))
            targets;
        syntheticAccessForwarding =
          import (builtins.getEnv "REPO_ROOT" + "/s88/ControlModule/firewall/lookup/forwarding-intent.nix") {
            lib = nixpkgsLib;
            runtimeTarget.forwardingIntent = {
              mode = "explicit-access-forwarding";
              rules = [
                {
                  action = "accept";
                  fromInterface = "core-nebula";
                  toInterface = "transit";
                  relationId = "runtime-origin-egress";
                  sourcePrefixes = [
                    {
                      family = 4;
                      prefix = "10.19.0.8/32";
                    }
                    {
                      family = 6;
                      prefix = "fd42:dead:beef:1900::8/128";
                    }
                  ];
                }
              ];
            };
            interfaces = {
              core-nebula.containerInterfaceName = "core-nebula";
              transit.containerInterfaceName = "transit";
            };
          };
        syntheticAccessRules =
          import (builtins.getEnv "REPO_ROOT" + "/s88/ControlModule/firewall/emission/default.nix") {
            lib = nixpkgsLib;
          } {
            tableName = "router";
            forwardPolicy = "drop";
            forwardPairs = syntheticAccessForwarding.accessForwardPairs;
          };
        sourceScopedRule = incomingInterface: prefix:
          builtins.filter
            (rule:
              (rule.IncomingInterface or null) == incomingInterface
              && (rule.From or null) == prefix
              && builtins.isInt (rule.Table or null)
              && !(rule ? SuppressPrefixLength))
            upstreamRules;
        hasPreferredRoute =
          builtins.any
            (route:
              (route.Destination or null) == "0.0.0.0/0"
              && (route.PreferredSource or null) == "10.19.0.8")
            coreNebulaRoutes;
        hasPreferredRoute6 =
          builtins.any
            (route:
              (route.Destination or null) == "::/0"
              && (route.PreferredSource or null) == "fd42:dead:beef:1900:0:0:0:8")
            coreNebulaRoutes;
        polClientATable =
          let matches = sourceScopedRule "pol-client-a" "10.19.0.8/32";
          in if matches == [ ] then null else (builtins.head matches).Table;
        polClientBTable =
          let matches = sourceScopedRule "pol-client-b" "10.19.0.8/32";
          in if matches == [ ] then null else (builtins.head matches).Table;
        hasRuntimeSourceRule = polClientATable != null && polClientBTable != null;
        hasRuntimeSourceRule6 =
          builtins.any
            (prefix:
              (sourceScopedRule "pol-client-a" prefix) != [ ]
              && (sourceScopedRule "pol-client-b" prefix) != [ ])
            [
              "fd42:dead:beef:1900::8/128"
              "fd42:dead:beef:1900:0:0:0:8/128"
              "fd42:dead:beef:1900:0000:0000:0000:0008/128"
            ];
        hasCrossLaneRuntimeSourceRule =
          builtins.any
            (rule:
              (rule.From or null) == "10.19.0.8/32"
              && (
                ((rule.IncomingInterface or null) == "pol-client-a" && (rule.Table or null) == polClientBTable)
                || ((rule.IncomingInterface or null) == "pol-client-b" && (rule.Table or null) == polClientATable)
              ))
            upstreamRules;
        policyDownstreamClientTable =
          let
            matches =
              builtins.filter
                (rule:
                  (rule.IncomingInterface or null) == "down-client"
                  && (rule.From or null) == "10.19.0.8/32"
                  && builtins.isInt (rule.Table or null)
                  && !(rule ? SuppressPrefixLength))
                policyDownstreamClientRules;
          in
          if matches == [ ] then null else (builtins.head matches).Table;
        hasPolicyRuntimeSourceRule =
          policyDownstreamClientTable != null;
        hasPolicyRuntimeSourceRule6 =
          builtins.any
            (rule:
              (rule.IncomingInterface or null) == "down-client"
              && (
                (rule.From or null) == "fd42:dead:beef:1900::8/128"
                || (rule.From or null) == "fd42:dead:beef:1900:0:0:0:8/128"
                || (rule.From or null) == "fd42:dead:beef:1900:0000:0000:0000:0008/128"
              )
              && builtins.isInt (rule.Table or null)
              && !(rule ? SuppressPrefixLength))
            policyDownstreamClientRules;
        hasPolicyClientDefault =
          builtins.any
              (route:
                (route.Table or null) == policyDownstreamClientTable
                && (route.Destination or null) == "0.0.0.0/0"
              && builtins.isInt (route.Metric or null)
              && (route.Metric or 9999) < 2000)
            (policyUpClientARoutes ++ policyUpClientBRoutes);
        hasPolicyRuntimeSourceMainRoute =
          builtins.any
            (route:
              (route.Destination or null) == "10.19.0.8/32"
              && (route.GatewayOnLink or false)
              && !(route ? Table))
            (policyDownstreamClientRoutes ++ policyRoutes);
        wrongPolicyRuntimeSourceMainRoutes =
          nixpkgsLib.concatLists (
            nixpkgsLib.mapAttrsToList
              (networkName: network:
                if networkName == "10-down-client" then
                  [ ]
                else
                  map
                    (route: { inherit networkName route; })
                    (builtins.filter
                      (route:
                        (route.Destination or null) == "10.19.0.8/32"
                        && !(route ? Table))
                      (network.routes or [ ])))
              policyNetworks
          );
        hasAccessRuntimeOriginAllow4 =
          nixpkgsLib.hasInfix
            "iifname \"core-nebula\" oifname \"transit\" ip saddr 10.19.0.8/32 accept comment \"runtime-origin-egress\""
            syntheticAccessRules;
        hasAccessRuntimeOriginAllow6 =
          nixpkgsLib.hasInfix
            "iifname \"core-nebula\" oifname \"transit\" ip6 saddr fd42:dead:beef:1900::8/128 accept comment \"runtime-origin-egress\""
            syntheticAccessRules;
        hasCoreADefault =
          builtins.any
            (route:
              (route.Destination or null) == "0.0.0.0/0"
              && (route.Gateway or null) == "10.10.0.12"
              && (route.Table or null) == polClientATable
              && builtins.isInt (route.Metric or null))
            upstreamRoutes;
        wrongDefaultRoutes =
          builtins.filter
            (route:
              builtins.elem (route.Table or null) [ polClientATable polClientBTable ]
              && (route.Destination or null) == "0.0.0.0/0"
              && (route.Metric or 1024) <= 50
              && !builtins.elem (route.Gateway or null) [ "10.10.0.12" "10.10.0.14" ])
            ((upstream.systemd.network.networks."10-core-nebula".routes or [ ])
             ++ (upstream.systemd.network.networks."10-pol-hostile-ew".routes or [ ]));
        result = {
          inherit
            hasPreferredRoute
            hasPreferredRoute6
            hasRuntimeSourceRule
            hasRuntimeSourceRule6
            hasPolicyRuntimeSourceRule
            hasPolicyRuntimeSourceRule6
            hasPolicyClientDefault
            hasPolicyRuntimeSourceMainRoute
            runtimeOriginHasAccessOrigin
            wrongPolicyRuntimeSourceMainRoutes
            hasAccessRuntimeOriginAllow4
            hasAccessRuntimeOriginAllow6
            hasCoreADefault
            wrongDefaultRoutes
            hasCrossLaneRuntimeSourceRule
            ;
        };
      in
        if
          result.hasPreferredRoute
          && result.hasPreferredRoute6
          && result.hasRuntimeSourceRule
          && result.hasRuntimeSourceRule6
          && result.hasPolicyRuntimeSourceRule
          && result.hasPolicyRuntimeSourceRule6
          && result.hasPolicyClientDefault
          && result.hasPolicyRuntimeSourceMainRoute
          && (!result.runtimeOriginHasAccessOrigin || result.wrongPolicyRuntimeSourceMainRoutes == [ ])
          && result.hasAccessRuntimeOriginAllow4
          && result.hasAccessRuntimeOriginAllow6
          && result.hasCoreADefault
          && result.wrongDefaultRoutes == [ ]
          && !result.hasCrossLaneRuntimeSourceRule
        then true
        else throw ("runtime-origin-loopback-egress-render failed: " + builtins.toJSON result)
    '

echo "PASS runtime-origin-loopback-egress-render"
