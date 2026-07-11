#!/usr/bin/env bash
# GAMP-ID: FS-380-HDS-020-SDS-010-SMS-120
# GAMP-SCOPE: software-module-test
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${repo_root}/tests/lib/test-common.sh"

labs_repo="${NETWORK_LABS_PATH:-${repo_root}/../network-labs}"
trace_id="FS-380-HDS-020-SDS-010-SMS-120"
tmp_dir="$(mktemp -d "${TMPDIR:-/tmp}/network-renderer-nixos-fs380-sms120.XXXXXX")"
trap 'rm -rf "${tmp_dir}"' EXIT
ln -s "${labs_repo}/GAMP" "${tmp_dir}/GAMP"
current_lab_dir="${tmp_dir}/current-lab"
NETWORK_LABS_CURRENT_LAB_DIR="${current_lab_dir}" \
  bash "${labs_repo}/scripts/select-current-lab.sh" SMT "${trace_id}" >/dev/null

metadata_path="${current_lab_dir}/metadata.nix"
intent_path="${current_lab_dir}/intent-s-router-nixos.nix"
inventory_path="${current_lab_dir}/inventory-s-router-nixos.nix"
cpm_repo="${NETWORK_CONTROL_PLANE_MODEL_PATH:-${repo_root}/../network-control-plane-model}"
if [[ ! -f "${cpm_repo}/flake.nix" ]]; then
  cpm_repo=""
fi

[[ -f "${metadata_path}" ]] || fail "missing selected network-labs current-lab metadata: ${metadata_path}"
[[ -f "${intent_path}" ]] || fail "missing current-lab NixOS intent fixture: ${intent_path}"
[[ -f "${inventory_path}" ]] || fail "missing current-lab NixOS inventory fixture: ${inventory_path}"

nix_eval_true_or_fail "FS-380 SMS-120 NixOS access IPv4 policy routing" \
  env REPO_ROOT="${repo_root}" \
    CURRENT_LAB_DIR="${current_lab_dir}" \
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
          metadata = import (builtins.getEnv "CURRENT_LAB_DIR" + "/metadata.nix");
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

nix_eval_true_or_fail "FS-380 SMS-120 NixOS prod-like access runtime-name policy routing" \
  env REPO_ROOT="${repo_root}" \
    CURRENT_LAB_DIR="${current_lab_dir}" \
    INTENT_PATH="${intent_path}" \
    INVENTORY_PATH="${inventory_path}" \
    CPM_REPO="${cpm_repo}" \
    nix eval \
      --extra-experimental-features 'nix-command flakes' \
      --impure --expr '
        let
          traceId = "FS-380-HDS-020-SDS-010-SMS-120";
          repoRoot = builtins.getEnv "REPO_ROOT";
          flake = builtins.getFlake ("path:" + repoRoot);
          cpmRepo = builtins.getEnv "CPM_REPO";
          cpmFlake =
            if cpmRepo != "" then
              builtins.getFlake ("path:" + cpmRepo)
            else
              flake.inputs.network-control-plane-model;
          lib = flake.inputs.nixpkgs.lib;
          system = "x86_64-linux";
          metadata = import (builtins.getEnv "CURRENT_LAB_DIR" + "/metadata.nix");
          input = import (builtins.getEnv "INTENT_PATH");
          baseInventory = import (builtins.getEnv "INVENTORY_PATH");
          accessNodeMatches =
            lib.filterAttrs
              (
                _: node:
                  ((node.logicalNode or { }).name or "") == "access-vlan2"
                  && ((node.logicalNode or { }).site or "") == traceId
              )
              (baseInventory.realization.nodes or { });
          accessNodeKeys = builtins.attrNames accessNodeMatches;
          accessNodeKey =
            if builtins.length accessNodeKeys == 1 then
              builtins.elemAt accessNodeKeys 0
            else
              throw "${traceId}: expected exactly one access-vlan2 realization node, got ${toString (builtins.length accessNodeKeys)}";
          p2pIfName = "p2p-access-vlan2-downstream-selector";
          tenantIfName = "tenant-client";
          accessNode = baseInventory.realization.nodes.${accessNodeKey};
          p2pPort = accessNode.ports.${p2pIfName};
          tenantPort = accessNode.ports.${tenantIfName};
          inventory =
            baseInventory
            // {
              realization =
                baseInventory.realization
                // {
                  nodes =
                    baseInventory.realization.nodes
                    // {
                      ${accessNodeKey} =
                        accessNode
                        // {
                          ports =
                            accessNode.ports
                            // {
                              ${p2pIfName} =
                                p2pPort
                                // {
                                  interface = (p2pPort.interface or { }) // {
                                    name = "access-vlan2";
                                  };
                                };
                              ${tenantIfName} =
                                tenantPort
                                // {
                                  interface = (tenantPort.interface or { }) // {
                                    name = "lan2";
                                  };
                                };
                            };
                        };
                    };
                };
            };
          cpm = cpmFlake.lib.${system}.compileAndBuild {
            inherit input inventory;
          };
          accessTarget = cpm.control_plane_model.data.mini-smt.${traceId}.runtimeTargets.${accessNodeKey};
          cpmP2p = accessTarget.effectiveRuntimeRealization.interfaces.${p2pIfName};
          cpmTenant = accessTarget.effectiveRuntimeRealization.interfaces.${tenantIfName};
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
          p2pRoutes = (networks."10-access-vlan2" or { }).routes or [ ];
          lan2Routes = (networks."10-lan2" or { }).routes or [ ];
          p2pRules = (networks."10-access-vlan2" or { }).routingPolicyRules or [ ];
          lan2Rules = (networks."10-lan2" or { }).routingPolicyRules or [ ];
          allRules = p2pRules ++ lan2Rules;
          isDefault =
            route:
              (route.Destination or null) == "0.0.0.0/0"
              || (route.Destination or null) == "::/0"
              || (route.Destination or null) == "0000:0000:0000:0000:0000:0000:0000:0000/0";
          isMainRoute = route: !(builtins.hasAttr "Table" route) || (route.Table or null) == 254;
          hasMainDefault =
            builtins.any (route: isDefault route && isMainRoute route) p2pRoutes;
          hasEgressPolicyDefault =
            builtins.any
              (
                route:
                  (route.Destination or null) == "0.0.0.0/0"
                  && (route.Gateway or null) == "10.10.0.1"
                  && (route.Table or null) == 1002
              )
              p2pRoutes;
          hasDefaultInReturnTable =
            builtins.any
              (
                route:
                  (route.Destination or null) == "0.0.0.0/0"
                  && (route.Table or null) == 1001
              )
              p2pRoutes;
          hasTenantReturnRoute =
            builtins.any
              (
                route:
                  (route.Destination or null) == "10.38.120.0/24"
                  && (route.Scope or null) == "link"
                  && (route.Table or null) == 1001
              )
              lan2Routes;
          hasTenantReturnRule =
            builtins.any
              (
                rule:
                  (rule.Family or null) == "ipv4"
                  && (rule.To or null) == "10.38.120.0/24"
                  && (rule.IncomingInterface or null) == "access-vlan2"
                  && (rule.Priority or null) == 1001
                  && (rule.Table or null) == 1001
              )
              allRules;
          hasClientEgressRule =
            builtins.any
              (
                rule:
                  (rule.Family or null) == "ipv4"
                  && (rule.From or null) == "10.38.120.0/24"
                  && (rule.IncomingInterface or null) == "lan2"
                  && (rule.Priority or null) == 1002
                  && (rule.Table or null) == 1002
              )
              allRules;
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
              p2pRules;
          require = cond: msg: if cond then true else throw msg;
        in
          require ((metadata.traceId or "") == traceId)
            "${traceId}: network-labs current-lab must be selected to the prod-like IPv4 SMS"
          && require ((cpmTenant.policyRoutingAllocation.tableId or null) == 1001)
            "${traceId}: CPM tenant return table must be 1001 under prod-like runtime names"
          && require ((cpmP2p.policyRoutingAllocation.tableId or null) == 1002)
            "${traceId}: CPM access-edge egress table must be 1002 under prod-like runtime names"
          && require (!hasMainDefault)
            "${traceId}: prod-like access-edge p2p must not emit a main-table default route"
          && require hasEgressPolicyDefault
            "${traceId}: prod-like access-edge p2p must keep egress default in policy table 1002"
          && require (!hasDefaultInReturnTable)
            "${traceId}: prod-like return table 1001 must not contain default reachability"
          && require hasTenantReturnRoute
            "${traceId}: prod-like tenant return table 1001 must route 10.38.120.0/24 through lan2"
          && require hasTenantReturnRule
            "${traceId}: prod-like transit ingress must select tenant return table 1001"
          && require hasClientEgressRule
            "${traceId}: prod-like client ingress must select access-edge egress table 1002 after return-table miss"
          && require hasLocalDnsOriginRule
            "${traceId}: prod-like access DNS local origin must use egress policy table 1002"
      '

echo "PASS FS-380-HDS-020-SDS-010-SMS-120 NixOS access IPv4 policy routing"
