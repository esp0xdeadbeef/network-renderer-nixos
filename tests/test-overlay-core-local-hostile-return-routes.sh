#!/usr/bin/env bash
set -euo pipefail
# LAB-SMT-ID: LAB-SMT-011
# LAB-SMT-SCOPE: examples-only; see network-labs/tests/SMT.md

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${repo_root}/tests/lib/test-common.sh"

example_root="${repo_root}/tests/fixtures/tri-site-s-router-overlay-egress"
intent_path="${example_root}/intent.nix"
inventory_path="${example_root}/inventory.nix"

[[ -f "${intent_path}" ]] || fail "missing intent: ${intent_path}"
[[ -f "${inventory_path}" ]] || fail "missing inventory: ${inventory_path}"

result_json="$(mktemp)"
eval_stderr="$(mktemp)"
trap 'rm -f "${result_json}" "${eval_stderr}"' EXIT

nix_eval_json_or_fail \
  overlay-core-local-hostile-return-routes \
  "${result_json}" \
  "${eval_stderr}" \
  env REPO_ROOT="${repo_root}" \
    INTENT_PATH="${intent_path}" \
    INVENTORY_PATH="${inventory_path}" \
    nix eval \
      --extra-experimental-features 'nix-command flakes' \
      --impure --json --expr '
        let
          flake = builtins.getFlake ("path:" + builtins.getEnv "REPO_ROOT");
          lib = flake.inputs.nixpkgs.lib;
          system = "x86_64-linux";
          built = import (builtins.getEnv "REPO_ROOT" + "/tests/nix/build-host-from-paths.nix") {
            selector = "s-router-test";
            inherit system;
            intentPath = builtins.getEnv "INTENT_PATH";
            inventoryPath = builtins.getEnv "INVENTORY_PATH";
          };
          cfg = (lib.nixosSystem {
            inherit system;
            modules = [ built.renderedHost.containers."home-example-router-core-nebula".config ];
          }).config;
          networks = cfg.systemd.network.networks;
          allRoutes =
            builtins.concatMap
              (networkName: map (route: route // { inherit networkName; }) (networks.${networkName}.routes or [ ]))
              (builtins.attrNames networks);
          hasRoute = destination: gateway: table:
            builtins.any
              (route:
                (route.networkName or null) == "10-upstream"
                && (route.Destination or null) == destination
                && (route.Gateway or null) == gateway
                && (route.GatewayOnLink or false)
                && ((route.Table or null) == table))
              allRoutes;
          readExecScript = service: builtins.readFile (lib.removeSuffix " " service.serviceConfig.ExecStart);
          routeServiceScripts =
            builtins.concatStringsSep "\n" (
              lib.mapAttrsToList
                (_: service: if service.serviceConfig ? ExecStart then readExecScript service else "")
                (lib.filterAttrs
                  (name: _: lib.hasPrefix "s88-delegated-prefix" name || lib.hasPrefix "s88-dynamic-route" name)
                  cfg.systemd.services)
            );
          hasRuntimeSourceFileRoute = table:
            lib.hasInfix "source_file=/run/secrets/access-node-ipv6-prefix-esp-home-example-router-access-hostile" routeServiceScripts
            && lib.hasInfix "interface=upstream" routeServiceScripts
            && lib.hasInfix "gateway=fd42:dead:beef:1000:0:0:0:11" routeServiceScripts
            && lib.hasInfix ("table=" + toString table) routeServiceScripts
            && lib.hasInfix "ip -6 route replace table \"$table\" \"$prefix\" via \"$gateway\" dev \"$interface\" proto static onlink" routeServiceScripts;
          checks = {
            main_hostile_v4_return =
              hasRoute "10.20.70.0/24" "10.10.0.17" null;
            main_hostile_ula_return =
              hasRoute "fd42:dead:beef:0070:0000:0000:0000:0000/64" "fd42:dead:beef:1000:0:0:0:11" null;
            table_2000_hostile_v4_return =
              hasRoute "10.20.70.0/24" "10.10.0.17" 2000;
            table_2000_hostile_ula_return =
              hasRoute "fd42:dead:beef:0070:0000:0000:0000:0000/64" "fd42:dead:beef:1000:0:0:0:11" 2000;
            table_2001_hostile_v4_return =
              hasRoute "10.20.70.0/24" "10.10.0.17" 2001;
            table_2001_hostile_ula_return =
              hasRoute "fd42:dead:beef:0070:0000:0000:0000:0000/64" "fd42:dead:beef:1000:0:0:0:11" 2001;
            runtime_hostile_gua_return_table_2000 =
              hasRuntimeSourceFileRoute 2000;
            runtime_hostile_gua_return_table_2001 =
              hasRuntimeSourceFileRoute 2001;
          };
        in
        {
          ok = builtins.all (name: checks.${name}) (builtins.attrNames checks);
          failed = builtins.filter (name: !(checks.${name})) (builtins.attrNames checks);
          inherit checks allRoutes routeServiceScripts;
        }
      '

assert_json_checks_ok overlay-core-local-hostile-return-routes "${result_json}"

echo "PASS overlay-core-local-hostile-return-routes"
