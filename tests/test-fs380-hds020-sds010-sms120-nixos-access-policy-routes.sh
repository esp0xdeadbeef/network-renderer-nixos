#!/usr/bin/env bash
# GAMP-ID: FS-380-HDS-020-SDS-010-SMS-120
# GAMP-SCOPE: software-module-test
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${repo_root}/tests/lib/test-common.sh"

labs_repo="${NETWORK_LABS_PATH:-${repo_root}/../network-labs}"
metadata_path="${labs_repo}/current-lab/metadata.nix"
intent_path="${labs_repo}/current-lab/intent-s-router-nixos.nix"
inventory_path="${labs_repo}/current-lab/inventory-s-router-nixos.nix"

[[ -f "${metadata_path}" ]] || fail "missing network-labs current-lab metadata: ${metadata_path}"
[[ -f "${intent_path}" ]] || fail "missing current-lab NixOS intent fixture: ${intent_path}"
[[ -f "${inventory_path}" ]] || fail "missing current-lab NixOS inventory fixture: ${inventory_path}"

nix_eval_true_or_fail "FS-380 SMS-120 NixOS access IPv4 policy routing" \
  env REPO_ROOT="${repo_root}" \
    NETWORK_LABS_PATH="${labs_repo}" \
    INTENT_PATH="${intent_path}" \
    INVENTORY_PATH="${inventory_path}" \
    nix eval \
      --extra-experimental-features 'nix-command flakes' \
      --impure --expr '
        let
          repoRoot = builtins.getEnv "REPO_ROOT";
          flake = builtins.getFlake ("path:" + repoRoot);
          lib = flake.inputs.nixpkgs.lib;
          system = "x86_64-linux";
          metadata = import (builtins.getEnv "NETWORK_LABS_PATH" + "/current-lab/metadata.nix");
          cpm = flake.inputs.network-control-plane-model.lib.${system}.compileAndBuildFromPaths {
            inputPath = builtins.getEnv "INTENT_PATH";
            inventoryPath = builtins.getEnv "INVENTORY_PATH";
            validateForwardingModel = false;
            validateRuntimeModel = false;
          };
          hostModule = flake.lib.renderer.hostModule {
            inherit lib system cpm;
            hostName = "s-router-nixos";
            selectorFile = "tests/test-fs380-hds020-sds010-sms120-nixos-access-policy-routes.sh";
          };
          evaluated = lib.nixosSystem {
            inherit system;
            modules = [ hostModule ];
          };
          networks = evaluated.config.containers."access-vlan2".config.systemd.network.networks or { };
          p0Routes = (networks."10-p0" or { }).routes or [ ];
          lan2Routes = (networks."10-lan2" or { }).routes or [ ];
          p0Rules = (networks."10-p0" or { }).routingPolicyRules or [ ];
          lan2Rules = (networks."10-lan2" or { }).routingPolicyRules or [ ];
          isDefault =
            route:
              (route.Destination or null) == "0.0.0.0/0"
              || (route.Destination or null) == "::/0"
              || (route.Destination or null) == "0000:0000:0000:0000:0000:0000:0000:0000/0";
          isMainRoute = route: !(builtins.hasAttr "Table" route) || (route.Table or null) == 254;
          hasMainDefault =
            builtins.any (route: isDefault route && isMainRoute route) p0Routes;
          hasPolicyDefault =
            builtins.any
              (
                route:
                  (route.Destination or null) == "0.0.0.0/0"
                  && (route.Gateway or null) == "10.10.0.1"
                  && (route.Table or null) == 1002
              )
              p0Routes;
          hasLan2ReturnRouteInReturnTable =
            builtins.any
              (
                route:
                  (route.Destination or null) == "10.38.120.0/24"
                  && (route.Scope or null) == "link"
                  && (route.Table or null) == 1001
              )
              lan2Routes;
          hasLan2ReturnRouteInPolicyTable =
            builtins.any
              (
                route:
                  (route.Destination or null) == "10.38.120.0/24"
                  && (route.Scope or null) == "link"
                  && (route.Table or null) == 1002
              )
              lan2Routes;
          hasLocalDnsOriginRule =
            builtins.any
              (
                rule:
                  (rule.Family or null) == "ipv4"
                  && (rule.From or null) == "10.38.120.1/32"
                  && (rule.Priority or null) == 1002
                  && (rule.Table or null) == 1002
                  && !(builtins.hasAttr "IncomingInterface" rule)
              )
              p0Rules;
          hasTransitIngressReturnRule =
            builtins.any
              (
                rule:
                  (rule.Family or null) == "ipv4"
                  && (rule.To or null) == "10.38.120.0/24"
                  && (rule.IncomingInterface or null) == "p0"
                  && (rule.Priority or null) == 1001
                  && (rule.Table or null) == 1001
              )
              (p0Rules ++ lan2Rules);
          require = cond: msg: if cond then true else throw msg;
        in
          require ((metadata.traceId or "") == "FS-380-HDS-020-SDS-010-SMS-120")
            "network-labs current-lab must be selected to FS-380-HDS-020-SDS-010-SMS-120"
          && require (!hasMainDefault)
            "access-vlan2 p0 must not emit a main-table default route; default egress belongs in the policy table"
          && require hasPolicyDefault
            "access-vlan2 p0 must keep the explicit IPv4 default in policy table 1002"
          && require hasLan2ReturnRouteInReturnTable
            "access-vlan2 must route transit-ingress replies to 10.38.120.0/24 through lan2 in table 1001"
          && require hasTransitIngressReturnRule
            "access-vlan2 must select table 1001 for transit-ingress replies to 10.38.120.0/24"
          && require hasLan2ReturnRouteInPolicyTable
            "access-vlan2 must route DNS local-origin replies to 10.38.120.0/24 through lan2 in table 1002"
          && require hasLocalDnsOriginRule
            "access-vlan2 must route local DNS source 10.38.120.1/32 through policy table 1002"
      '

echo "PASS FS-380-HDS-020-SDS-010-SMS-120 NixOS access IPv4 policy routing"
