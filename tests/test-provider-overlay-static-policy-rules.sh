#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${repo_root}/tests/lib/test-common.sh"

result_json="$(mktemp)"
eval_stderr="$(mktemp)"
trap 'rm -f "${result_json}" "${eval_stderr}"' EXIT

nix_eval_json_or_fail \
  provider-overlay-static-policy-rules \
  "${result_json}" \
  "${eval_stderr}" \
  env REPO_ROOT="${repo_root}" \
    nix eval \
    --extra-experimental-features 'nix-command flakes' \
    --impure --json --expr '
      let
        flake = builtins.getFlake ("path:" + builtins.getEnv "REPO_ROOT");
        lib = flake.inputs.nixpkgs.lib;
        system = "x86_64-linux";
        example = flake.inputs.network-labs + "/examples/s-router-overlay-dns-lane-policy";
        builtHost = flake.lib.renderer.buildHostFromPaths {
          intentPath = example + "/intent.nix";
          inventoryPath = example + "/inventory-nixos.nix";
          selector = "s-router-test";
        };
        cfg = (flake.inputs.nixpkgs.lib.nixosSystem {
          inherit system;
          modules = [ builtHost.renderedHost.containers.b-router-core-nebula.config ];
        }).config;
        providerPolicyRuleServices =
          lib.filterAttrs (name: _: lib.hasPrefix "s88-provider-policy-rule-nebula1-" name) cfg.systemd.services;
        providerRouteServices =
          lib.filterAttrs (name: _: lib.hasPrefix "s88-provider-route-nebula1-" name) cfg.systemd.services;
        providerPolicyRulePaths =
          lib.filterAttrs (name: _: lib.hasPrefix "s88-provider-policy-rule-nebula1-" name) cfg.systemd.paths;
        providerRoutePaths =
          lib.filterAttrs (name: _: lib.hasPrefix "s88-provider-route-nebula1-" name) cfg.systemd.paths;
        serviceScripts =
          lib.mapAttrsToList
            (_: service: builtins.readFile service.serviceConfig.ExecStart)
            providerPolicyRuleServices;
        dynamicScripts =
          lib.mapAttrsToList
            (_: service: builtins.readFile service.serviceConfig.ExecStart)
            (lib.filterAttrs (name: _: lib.hasPrefix "s88-dynamic-policy-rule-" name) cfg.systemd.services);
        scripts = builtins.concatStringsSep "\n" serviceScripts;
        dynamic = builtins.concatStringsSep "\n" dynamicScripts;
        has = lib.hasInfix;
        providerServices = (builtins.attrValues providerPolicyRuleServices) ++ (builtins.attrValues providerRouteServices);
        providerPaths = (lib.mapAttrsToList (name: value: { inherit name value; }) providerPolicyRulePaths)
          ++ (lib.mapAttrsToList (name: value: { inherit name value; }) providerRoutePaths);
        checks = {
          provider_units_wait_for_runtime_interface =
            (builtins.length providerPaths) >= 4
            && builtins.all
              (entry:
                (entry.value.pathConfig.PathExists or null) == "/sys/class/net/nebula1"
                && (entry.value.pathConfig.Unit or null) == "${entry.name}.service")
              providerPaths
            && builtins.all (service: (service.wantedBy or []) == []) providerServices;
          installs_hostile_v4_source_rule =
            has "rule add from '10.70.10.0/24' iif 'upstream' table '2000' priority '2000'" scripts;
          installs_hostile_ula_source_rule =
            has "rule add from 'fd42:dead:feed:0070:0000:0000:0000:0000/64' iif 'upstream' table '2000' priority '2000'" scripts;
          installs_main_suppress_fallback =
            has "rule add from '10.70.10.0/24' iif 'upstream' table main suppress_prefixlength '0' priority '12000'" scripts;
          keeps_dynamic_runtime_gua_source_file_rule =
            has "source_file='/run/secrets/access-node-ipv6-prefix-espbranch-site-b-b-router-access-hostile'" dynamic
            && has "interface='upstream'" dynamic
            && has "table='2000'" dynamic;
          no_unscoped_underlay_overlay_provider_rule =
            !(has "rule add iif 'upstream' table '2000' priority '2000'" scripts);
        };
      in
      {
        ok = builtins.all (name: checks.${name}) (builtins.attrNames checks);
        failed = builtins.filter (name: !(checks.${name})) (builtins.attrNames checks);
        inherit checks scripts dynamic;
      }
    '

assert_json_checks_ok provider-overlay-static-policy-rules "${result_json}"

echo "PASS provider-overlay-static-policy-rules"
