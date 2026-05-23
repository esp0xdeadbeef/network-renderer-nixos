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
        built = flake.lib.renderer.buildHostFromPaths {
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
        upstreamRules = upstream.systemd.network.networks."10-core-nebula".routingPolicyRules or [ ];
        upstreamRoutes = upstream.systemd.network.networks."10-core-a".routes or [ ];
        policyDownstreamClientRules = policy.systemd.network.networks."10-downstr-client".routingPolicyRules or [ ];
        policyUpClientARoutes = policy.systemd.network.networks."10-up-client-a".routes or [ ];
        policyUpClientBRoutes = policy.systemd.network.networks."10-up-client-b".routes or [ ];
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
        coreNebulaTable =
          let
            matches =
              builtins.filter
                  (rule:
                  (rule.IncomingInterface or null) == "core-nebula"
                  && (rule.From or null) == "10.19.0.8/32"
                  && builtins.isInt (rule.Table or null)
                  && !(rule ? SuppressPrefixLength))
                upstreamRules;
          in
          if matches == [ ] then null else (builtins.head matches).Table;
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
        hasRuntimeSourceRule =
          builtins.any
            (rule:
              (rule.IncomingInterface or null) == "core-nebula"
              && (rule.From or null) == "10.19.0.8/32"
              && builtins.isInt (rule.Table or null))
            upstreamRules;
        hasRuntimeSourceRule6 =
          builtins.any
            (rule:
              (rule.IncomingInterface or null) == "core-nebula"
              && (rule.From or null) == "fd42:dead:beef:1900:0000:0000:0000:0008/128"
              && builtins.isInt (rule.Table or null))
            upstreamRules;
        policyDownstreamClientTable =
          let
            matches =
              builtins.filter
                (rule:
                  (rule.IncomingInterface or null) == "downstr-client"
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
              (rule.IncomingInterface or null) == "downstr-client"
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
              && (route.Metric or null) == 50)
            (policyUpClientARoutes ++ policyUpClientBRoutes);
        hasBroadCoreNebulaRule =
          builtins.any
            (rule:
              (rule.IncomingInterface or null) == "core-nebula"
              && builtins.isInt (rule.Table or null)
              && !(rule ? From))
            upstreamRules;
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
              && (route.Table or null) == coreNebulaTable
              && (route.Metric or null) == 50)
            upstreamRoutes;
        wrongDefaultRoutes =
          builtins.filter
            (route:
              (route.Table or null) == coreNebulaTable
              && (route.Destination or null) == "0.0.0.0/0"
              && (route.Metric or 1024) <= 50
              && (route.Gateway or null) != "10.10.0.12")
            ((upstream.systemd.network.networks."10-core-nebula".routes or [ ])
             ++ (upstream.systemd.network.networks."10-pol-hostile-ew".routes or [ ]));
      in
        hasPreferredRoute
        && hasPreferredRoute6
        && hasRuntimeSourceRule
        && hasRuntimeSourceRule6
        && hasPolicyRuntimeSourceRule
        && hasPolicyRuntimeSourceRule6
        && hasPolicyClientDefault
        && hasAccessRuntimeOriginAllow4
        && hasAccessRuntimeOriginAllow6
        && hasCoreADefault
        && wrongDefaultRoutes == [ ]
        && !hasBroadCoreNebulaRule
    '

echo "PASS runtime-origin-loopback-egress-render"
