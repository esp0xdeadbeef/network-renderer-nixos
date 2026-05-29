#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${repo_root}/tests/lib/test-common.sh"

nix_eval_true_or_fail \
  downstream-selector-explicit-access-owner-return-routes \
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
              { action = "accept"; fromInterface = "access-stream"; toInterface = "policy-stream"; }
              { action = "accept"; fromInterface = "policy-stream"; toInterface = "access-stream"; }
            ];
            containerModel = {
              networkBehavior = {
                isSelector = true;
                isDownstreamSelector = true;
              };
              site = {
                tenants = [
                  {
                    name = "streaming";
                    ipv4 = "10.20.50.0/24";
                    ipv6 = "fd42:dead:beef:50::/64";
                  }
                ];
                tenantPrefixOwners = {
                  "4|10.20.50.0/24" = {
                    dst = "10.20.50.0/24";
                    family = 4;
                    netName = "streaming";
                    owner = "router-access-streaming";
                  };
                  "6|fd42:dead:beef:50::/64" = {
                    dst = "fd42:dead:beef:50::/64";
                    family = 6;
                    netName = "streaming";
                    owner = "router-access-streaming";
                  };
                };
              };
              interfaces = {
                access-stream = {
                  containerInterfaceName = "access-stream";
                  addresses = [
                    "10.10.0.11/31"
                    "fd42:dead:beef:1000::b/127"
                  ];
                  interfaceClass.edgeFacing = true;
                  backingRef.lane.access = "router-access-streaming";
                  routes = [ ];
                };
                policy-stream = {
                  containerInterfaceName = "policy-stream";
                  addresses = [
                    "10.10.0.28/31"
                    "fd42:dead:beef:1000::1c/127"
                  ];
                  interfaceClass.fabricFacing = true;
                  backingRef.lane.access = "router-access-streaming";
                  routes = [
                    {
                      dst = "0.0.0.0/0";
                      via4 = "10.10.0.29";
                      policyOnly = true;
                      reason = "policy-derived-default";
                      lane.access = "router-access-streaming";
                      lane.uplink = "isp-a";
                    }
                    {
                      dst = "::/0";
                      via6 = "fd42:dead:beef:1000::1d";
                      policyOnly = true;
                      reason = "policy-derived-default";
                      lane.access = "router-access-streaming";
                      lane.uplink = "isp-a";
                    }
                  ];
                };
              };
            };
          };
        networks = render.networks;
        rules = networks."10-policy-stream".routingPolicyRules or [ ];
        tableRules =
          builtins.filter
            (rule:
              (rule.IncomingInterface or null) == "policy-stream"
              && builtins.isInt (rule.Table or null)
              && (rule.Table or null) != 254)
            rules;
        table = if tableRules == [ ] then null else (builtins.head tableRules).Table;
        accessRoutes = networks."10-access-stream".routes or [ ];
        hasV4Return =
          table != null
          && builtins.any
            (route:
              (route.Destination or null) == "10.20.50.0/24"
              && (route.Gateway or null) == "10.10.0.10"
              && (route.Table or null) == table)
            accessRoutes;
        hasV6Return =
          table != null
          && builtins.any
            (route:
              (route.Destination or null) == "fd42:dead:beef:50::/64"
              && (route.Gateway or null) == "fd42:dead:beef:1000::a"
              && (route.Table or null) == table)
            accessRoutes;
      in
        if hasV4Return && hasV6Return then true else throw ("downstream selector return table must use explicit access owner metadata for streaming-like tenants: " + builtins.toJSON {
          inherit table accessRoutes rules;
        })
    '

echo "PASS downstream-selector-explicit-access-owner-return-routes"
