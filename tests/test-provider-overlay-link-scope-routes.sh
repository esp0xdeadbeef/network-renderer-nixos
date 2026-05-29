#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${repo_root}/tests/lib/test-common.sh"

result_json="$(mktemp)"
eval_stderr="$(mktemp)"
trap 'rm -f "${result_json}" "${eval_stderr}"' EXIT

nix_eval_json_or_fail \
  provider-overlay-link-scope-routes \
  "${result_json}" \
  "${eval_stderr}" \
  env REPO_ROOT="${repo_root}" \
    nix eval \
    --extra-experimental-features 'nix-command flakes' \
    --impure --json --expr '
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
              { action = "accept"; fromInterface = "upstream"; toInterface = "overlay-west"; }
              { action = "accept"; fromInterface = "overlay-west"; toInterface = "upstream"; }
            ];
            containerModel = {
              interfaces = {
                upstream = {
                  containerInterfaceName = "upstream";
                  addresses = [ "10.10.0.2/31" "fd42:dead:beef:1000::10/127" ];
                  interfaceClass.fabricFacing = true;
                  routes = [
                    {
                      dst = "0.0.0.0/0";
                      via4 = "10.10.0.3";
                    }
                    {
                      dst = "::/0";
                      via6 = "fd42:dead:beef:1000::11";
                      family = 6;
                    }
                  ];
                };
              };
              runtimeTarget.effectiveRuntimeRealization.interfaces.overlay-east-west = {
                sourceKind = "overlay";
                renderedIfName = "overlay-west";
                runtimeIfName = "overlay-west";
                routes = {
                  ipv4 = [
                    {
                      dst = "10.20.70.0/24";
                      family = 4;
                      proto = "overlay";
                      intent.kind = "overlay-reachability";
                    }
                  ];
                  ipv6 = [
                    {
                      dst = "fd42:dead:beef:70::/64";
                      family = 6;
                      proto = "overlay";
                      intent.kind = "overlay-reachability";
                    }
                  ];
                };
                materialization.nixos.ownsInterface = false;
              };
            };
          };
        routes = render.staticProviderRoutes;
        hasProviderRoute = destination: table:
          builtins.any
            (route:
              (route.interfaceName or null) == "overlay-west"
              && (route.destination or null) == destination
              && (route.table or null) == table
              && (route.scope or null) == "link"
              && (route.gateway or null) == null)
            routes;
        checks = {
          hostile_v4_overlay_route_table_2000 = hasProviderRoute "10.20.70.0/24" 2000;
          hostile_ula_overlay_route_table_2000 = hasProviderRoute "fd42:dead:beef:70::/64" 2000;
          hostile_v4_overlay_route_table_2001 = hasProviderRoute "10.20.70.0/24" 2001;
          hostile_ula_overlay_route_table_2001 = hasProviderRoute "fd42:dead:beef:70::/64" 2001;
        };
      in
      {
        ok = builtins.all (name: checks.${name}) (builtins.attrNames checks);
        failed = builtins.filter (name: !(checks.${name})) (builtins.attrNames checks);
        inherit checks routes;
      }
    '

assert_json_checks_ok provider-overlay-link-scope-routes "${result_json}"

echo "PASS provider-overlay-link-scope-routes"
