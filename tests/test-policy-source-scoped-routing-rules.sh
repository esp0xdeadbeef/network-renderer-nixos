#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${repo_root}/tests/lib/test-common.sh"

nix_eval_true_or_fail \
  policy-source-scoped-routing-rules \
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
                  fromInterface = "downstream-hostile";
                  toInterface = "up-hostile-ew";
                }
              ];
            };
            containerModel = {
              networkBehavior.isPolicy = true;
              site.tenantPrefixOwners = {
                "4|10.20.70.0/24".owner = "router-access-hostile";
                "6|fd42:dead:beef:0070:0000:0000:0000:0000/64".owner = "router-access-hostile";
                "6|source:/run/secrets/access-node-ipv6-prefix-router-access-hostile".owner = "router-access-hostile";
                "4|10.20.20.0/24".owner = "router-access-client";
              };
              policyRoutingSources.downstream-hostile = [ "downstream-hostile" "up-hostile-ew" ];
              interfaces = {
                downstream-hostile = {
                  containerInterfaceName = "downstream-hostile";
                  addresses = [ "10.50.0.32/31" ];
                  interfaceClass.fabricFacing = true;
                  backingRef.lane.access = "router-access-hostile";
                  routes = [ ];
                };
                up-hostile-ew = {
                  containerInterfaceName = "up-hostile-ew";
                  addresses = [ "10.50.0.34/31" ];
                  interfaceClass.exitFacing = true;
                  backingRef.lane = {
                    access = "router-access-hostile";
                    uplink = "east-west";
                    uplinks = [ "east-west" ];
                  };
                  routes = [
                    {
                      dst = "0.0.0.0/0";
                      via4 = "10.50.0.35";
                      policyOnly = true;
                      reason = "policy-derived-default";
                      lane.access = "router-access-hostile";
                      lane.uplink = "east-west";
                    }
                  ];
                };
              };
            };
          };
        rules = render.networks."10-downstream-hostile".routingPolicyRules or [ ];
        dynamicRules = render.dynamicPolicySourceRules or [ ];
        tableRules =
          builtins.filter
            (rule:
              (rule.IncomingInterface or null) == "downstream-hostile"
              && builtins.isInt (rule.Table or null)
              && (rule.Table or null) != 254)
            rules;
        broadTableRules = builtins.filter (rule: !(rule ? From) && !(rule ? To)) tableRules;
        hasFrom = prefix:
          builtins.any
            (rule:
              (rule.From or null) == prefix
              && (rule.IncomingInterface or null) == "downstream-hostile")
            tableRules;
        hasDynamic =
          builtins.any
            (rule:
              (rule.sourceFile or null) == "/run/secrets/access-node-ipv6-prefix-router-access-hostile"
              && (rule.interfaceName or null) == "downstream-hostile"
              && (rule.table or null) != 254)
            dynamicRules;
      in
        broadTableRules == [ ]
        && hasFrom "10.20.70.0/24"
        && hasFrom "fd42:dead:beef:0070:0000:0000:0000:0000/64"
        && !(hasFrom "10.20.20.0/24")
        && hasDynamic
    '

echo "PASS policy-source-scoped-routing-rules"
