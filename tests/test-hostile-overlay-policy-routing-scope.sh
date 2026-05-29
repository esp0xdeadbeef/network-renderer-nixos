#!/usr/bin/env bash
# GAMP-ID: SMT-NIXOS-POLICY-ROUTING-AGG-001
# SDS: SDS-SW-021-005, UP-006-OP-001-PH-002
# SMS: SMS-MOD-007-003
# CMC: CMC-MOD-006-004, CMC-FUNC-POLICY-ROUTING-001..010
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${repo_root}/tests/lib/test-common.sh"

nix_eval_true_or_fail \
  hostile-overlay-policy-routing-scope \
  env REPO_ROOT="${repo_root}" \
    nix eval \
    --extra-experimental-features 'nix-command flakes' \
    --impure --expr '
      let
        repoRoot = builtins.getEnv "REPO_ROOT";
        flake = builtins.getFlake ("path:" + repoRoot);
        lib = flake.inputs.nixpkgs.lib;
        render = args:
          import (repoRoot + "/s88/ControlModule/render/container-networks.nix") ({
            inherit lib;
            uplinks = { };
            wanUplinkName = null;
          } // args);
        tableRulesFor = network: interface:
          builtins.filter
            (rule:
              (rule.IncomingInterface or null) == interface
              && builtins.isInt (rule.Table or null)
              && (rule.Table or null) != 254)
            (network.routingPolicyRules or [ ]);
        hasSourceRule = network: interface: prefix:
          builtins.any (rule: (rule.From or null) == prefix) (tableRulesFor network interface);
        hasRoute = network: destination: gateway:
          builtins.any
            (route:
              (route.Destination or null) == destination
              && (route.Gateway or null) == gateway
              && builtins.isInt (route.Table or null))
            (network.routes or [ ]);
        hostileGua = "2a01:4f9:c01f:8034::/64";
        upstreamRender = render {
          forwardingIntent.rules = [
            { action = "accept"; fromInterface = "pol-hostile-ew"; toInterface = "core-nebula"; }
            { action = "accept"; fromInterface = "core-nebula"; toInterface = "pol-hostile-ew"; }
            {
              action = "accept";
              fromInterface = "core-nebula";
              toInterface = "core-a";
              trafficType = "nebula-runtime";
            }
            {
              action = "accept";
              fromInterface = "core-a";
              toInterface = "core-nebula";
              trafficType = "nebula-runtime";
            }
          ];
          containerModel = {
            networkBehavior.isUpstreamSelector = true;
            site.tenantPrefixOwners = {
              "4|10.20.70.0/24".owner = "router-access-hostile";
              "6|2a01:4f9:c01f:8034::/64".owner = "router-access-hostile";
            };
            policyRoutingSources.core-nebula = [
              "core-nebula"
              "core-a"
              "pol-hostile-ew"
            ];
            interfaces = {
              core-a = {
                containerInterfaceName = "core-a";
                addresses = [ "10.10.0.13/31" "fd42:dead:beef:1000::d/127" ];
                interfaceClass.coreFacing = true;
                backingRef.lane = {
                  uplink = "isp-a";
                  uplinks = [ "isp-a" ];
                };
                routes = [
                  {
                    dst = "0.0.0.0/0";
                    via4 = "10.10.0.12";
                    policyOnly = true;
                    lane.uplink = "isp-a";
                  }
                  {
                    dst = "::/0";
                    via6 = "fd42:dead:beef:1000::c";
                    policyOnly = true;
                    lane.uplink = "isp-a";
                  }
                ];
              };
              core-nebula = {
                containerInterfaceName = "core-nebula";
                addresses = [ "10.10.0.17/31" "fd42:dead:beef:1000::11/127" ];
                interfaceClass.coreFacing = true;
                backingRef.lane = {
                  uplink = "east-west";
                  uplinks = [ "east-west" ];
                };
                routes = [
                  {
                    dst = "0.0.0.0/0";
                    via4 = "10.10.0.16";
                    policyOnly = true;
                    lane.uplink = "east-west";
                  }
                  {
                    dst = "::/0";
                    via6 = "fd42:dead:beef:1000::10";
                    policyOnly = true;
                    lane.uplink = "east-west";
                  }
                ];
              };
              pol-hostile-ew = {
                containerInterfaceName = "pol-hostile-ew";
                addresses = [ "10.10.0.39/31" "fd42:dead:beef:1000::27/127" ];
                interfaceClass.exitFacing = true;
                backingRef.lane = {
                  access = "router-access-hostile";
                  uplink = "east-west";
                  uplinks = [ "east-west" ];
                };
              };
            };
          };
        };
        policyRender = render {
          forwardingIntent.rules = [
            { action = "accept"; fromInterface = "downstr-hostile"; toInterface = "up-hostile-ew"; }
            {
              action = "accept";
              fromInterface = "up-hostile-ew";
              toInterface = "downstr-hostile";
              sourcePrefixes = [
                { family = 6; prefix = hostileGua; }
              ];
            }
          ];
          containerModel = {
            networkBehavior.isPolicy = true;
            site.tenantPrefixOwners = {
              "4|10.20.15.0/24".owner = "router-access-admin";
              "4|10.20.20.0/24".owner = "router-access-client";
              "4|10.20.30.0/24".owner = "router-access-mgmt";
              "4|10.20.50.0/24".owner = "router-access-stream";
              "4|10.20.70.0/24".owner = "router-access-hostile";
              "6|2a01:4f9:c01f:8034::/64".owner = "router-access-hostile";
            };
            interfaces = {
              downstr-admin = {
                containerInterfaceName = "downstr-admin";
                addresses = [ "10.10.0.19/31" ];
                interfaceClass.fabricFacing = true;
                backingRef.lane.access = "router-access-admin";
              };
              downstr-client = {
                containerInterfaceName = "downstr-client";
                addresses = [ "10.10.0.21/31" ];
                interfaceClass.fabricFacing = true;
                backingRef.lane.access = "router-access-client";
              };
              downstream-mgmt = {
                containerInterfaceName = "downstream-mgmt";
                addresses = [ "10.10.0.23/31" ];
                interfaceClass.fabricFacing = true;
                backingRef.lane.access = "router-access-mgmt";
              };
              downstr-stream = {
                containerInterfaceName = "downstr-stream";
                addresses = [ "10.10.0.37/31" ];
                interfaceClass.fabricFacing = true;
                backingRef.lane.access = "router-access-stream";
              };
              downstr-hostile = {
                containerInterfaceName = "downstr-hostile";
                addresses = [ "10.10.0.25/31" ];
                interfaceClass.fabricFacing = true;
                backingRef.lane.access = "router-access-hostile";
              };
              up-hostile-ew = {
                containerInterfaceName = "up-hostile-ew";
                addresses = [ "10.10.0.38/31" ];
                interfaceClass.exitFacing = true;
                backingRef.lane = {
                  access = "router-access-hostile";
                  uplink = "east-west";
                  uplinks = [ "east-west" ];
                };
                routes = [
                  {
                    dst = "::/0";
                    via6 = "fd42:dead:beef:1000::27";
                    policyOnly = true;
                    lane.access = "router-access-hostile";
                    lane.uplink = "east-west";
                  }
                ];
              };
            };
          };
        };
        upstreamCoreNebula = upstreamRender.networks."10-core-nebula";
        policyUpHostile = policyRender.networks."10-up-hostile-ew";
      in
        if hasRoute upstreamCoreNebula "0.0.0.0/0" "10.10.0.12" then
          throw "L4-only core-nebula -> core-a accept projected the core-a IPv4 default into the core-nebula table"
        else if hasRoute upstreamCoreNebula "::/0" "fd42:dead:beef:1000::c" then
          throw "L4-only core-nebula -> core-a accept projected the core-a IPv6 default into the core-nebula table"
        else if !(hasRoute upstreamCoreNebula "0.0.0.0/0" "10.10.0.16") then
          throw "core-nebula table lost its modeled hostile east-west IPv4 default"
        else if !(hasRoute upstreamCoreNebula "::/0" "fd42:dead:beef:1000::10") then
          throw "core-nebula table lost its modeled hostile east-west IPv6 default"
        else if !(hasSourceRule upstreamCoreNebula "pol-hostile-ew" "10.20.70.0/24") then
          throw "pol-hostile-ew ingress lost hostile IPv4 source scope into the core-nebula table"
        else if !(hasSourceRule upstreamCoreNebula "pol-hostile-ew" hostileGua) then
          throw "pol-hostile-ew ingress lost hostile GUA source scope into the core-nebula table"
        else if !(hasSourceRule policyUpHostile "downstr-hostile" hostileGua) then
          throw "hostile downstream ingress lost hostile GUA source scope into the hostile policy table"
        else if hasSourceRule policyUpHostile "downstr-admin" hostileGua then
          throw "hostile GUA source scope leaked onto admin downstream ingress"
        else if hasSourceRule policyUpHostile "downstr-client" hostileGua then
          throw "hostile GUA source scope leaked onto client downstream ingress"
        else if hasSourceRule policyUpHostile "downstream-mgmt" hostileGua then
          throw "hostile GUA source scope leaked onto mgmt downstream ingress"
        else if hasSourceRule policyUpHostile "downstr-stream" hostileGua then
          throw "hostile GUA source scope leaked onto streaming downstream ingress"
        else
          true
    '

echo "PASS hostile-overlay-policy-routing-scope"
