#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${repo_root}/tests/lib/test-common.sh"

example_root="$(flake_input_path network-labs)/examples/s-router-test-three-site"
intent_path="${example_root}/intent.nix"
inventory_path="${example_root}/inventory-nixos.nix"

[[ -f "${intent_path}" ]] || { echo "missing intent: ${intent_path}" >&2; exit 1; }
[[ -f "${inventory_path}" ]] || { echo "missing inventory: ${inventory_path}" >&2; exit 1; }

result_json="$(mktemp)"
eval_stderr="$(mktemp)"
trap 'rm -f "${result_json}" "${eval_stderr}"' EXIT

nix_eval_json_or_fail \
  dns-service-policy-routes \
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
        builtContainers = flake.lib.containers.buildForBox {
          boxName = "s-router-test";
          system = "x86_64-linux";
          intentPath = builtins.getEnv "INTENT_PATH";
          inventoryPath = builtins.getEnv "INVENTORY_PATH";
        };
        builtHetznerContainers = flake.lib.containers.buildForBox {
          boxName = "s-router-hetzner-anywhere";
          system = "x86_64-linux";
          intentPath = builtins.getEnv "INTENT_PATH";
          inventoryPath = builtins.getEnv "INVENTORY_PATH";
        };
        mkCfgFrom = containers: containerName:
          (flake.inputs.nixpkgs.lib.nixosSystem {
            system = "x86_64-linux";
            modules = [ containers.${containerName}.config ];
          }).config;
        mkCfg = mkCfgFrom builtContainers;
        mkHetznerCfg = mkCfgFrom builtHetznerContainers;
        branchCfg = mkCfg "b-router-policy";
        branchUpstreamCfg = mkCfg "b-router-upstream-selector";
        siteaUpstreamCfg = mkCfg "s-router-upstream-selector";
        siteaPolicyCfg = mkCfg "s-router-policy-only";
        sitecCfg = mkHetznerCfg "c-router-policy";
        hasRoute = routes: destination: gateway: table:
          builtins.any
            (route:
              (route.Destination or null) == destination
              && (route.Gateway or null) == gateway
              && (route.Table or null) == table)
            routes;
        missingRoute = routes: destination: gateway: table:
          !(hasRoute routes destination gateway table);
        hasRouteAnyNetwork = networks: destination: gateway: table:
          builtins.any
            (networkName: hasRoute (networks.${networkName}.routes or [ ]) destination gateway table)
            (builtins.attrNames networks);
        branchNetworks = branchCfg.systemd.network.networks;
        branchUpstreamNetworks = branchUpstreamCfg.systemd.network.networks;
        siteaUpstreamNetworks = siteaUpstreamCfg.systemd.network.networks;
        siteaPolicyNetworks = siteaPolicyCfg.systemd.network.networks;
        sitecNetworks = sitecCfg.systemd.network.networks;
        siteaPolicyRules = siteaPolicyCfg.networking.nftables.ruleset;
        bUpstreamCoreIngressRoutes =
          (branchUpstreamNetworks."10-pol-branch-ew".routes or [ ])
          ++ (branchUpstreamNetworks."10-pol-hostile-ew".routes or [ ]);
        siteaMgmtRoutes = siteaPolicyNetworks."10-downstream-mgmt".routes or [ ];
        siteaMgmtWanReturnRoutes = siteaUpstreamNetworks."10-pol-mgmt-a".routes or [ ];
        siteaMgmtEastWestReturnRoutes = siteaUpstreamNetworks."10-pol-mgt-ew".routes or [ ];
        sitecClientRoutes = sitecNetworks."10-downstr-client".routes or [ ];
        checks = {
          branch_v4_dns_route =
            hasRouteAnyNetwork branchNetworks "10.20.10.0/24" "10.50.0.13" 2000;
          branch_v6_dns_route =
            hasRouteAnyNetwork branchNetworks "fd42:dead:beef:0010:0000:0000:0000:0000/64" "fd42:dead:feed:1000:0:0:0:d" 2000;
          branch_upstream_branch_return =
            hasRoute bUpstreamCoreIngressRoutes "10.50.0.0/31" "10.50.0.12" 2000;
          branch_upstream_hostile_return =
            hasRoute bUpstreamCoreIngressRoutes "10.50.0.2/31" "10.50.0.16" 2000;
          branch_upstream_wrong_v4_absent =
            missingRoute bUpstreamCoreIngressRoutes "10.50.0.0" "10.50.0.16" 2000;
          branch_upstream_wrong_v6_absent =
            missingRoute bUpstreamCoreIngressRoutes "fd42:dead:feed:1000:0:0:0:0" "fd42:dead:feed:1000:0:0:0:10" 2000;
          sitea_upstream_dns_route =
            hasRouteAnyNetwork siteaUpstreamNetworks "10.20.10.0/24" "10.10.0.48" 2002;
          sitea_upstream_wrong_lane_absent =
            !(hasRouteAnyNetwork siteaUpstreamNetworks "10.20.10.0/24" "10.10.0.30" 2001);
          sitea_mgmt_wan_dns_v4 =
            hasRoute siteaMgmtWanReturnRoutes "10.20.10.0/24" "10.10.0.50" 2000;
          sitea_mgmt_wan_p2p_v4 =
            hasRoute siteaMgmtWanReturnRoutes "10.10.0.8/31" "10.10.0.50" 2000;
          sitea_mgmt_wan_dns_v6 =
            hasRoute siteaMgmtWanReturnRoutes "fd42:dead:beef:10::/64" "fd42:dead:beef:1000:0:0:0:32" 2000;
          sitea_mgmt_wan_p2p_v6 =
            hasRoute siteaMgmtWanReturnRoutes "fd42:dead:beef:1000:0:0:0:8/127" "fd42:dead:beef:1000:0:0:0:32" 2000;
          sitea_mgmt_ew_branch_p2p_v4 =
            hasRoute siteaMgmtEastWestReturnRoutes "10.50.0.0/31" "10.10.0.48" 2002;
          sitea_mgmt_ew_branch_p2p_v6 =
            hasRoute siteaMgmtEastWestReturnRoutes "fd42:dead:feed:1000:0:0:0:0/127" "fd42:dead:beef:1000:0:0:0:30" 2002;
          sitea_mgmt_downstream_dns_v4 =
            hasRoute siteaMgmtRoutes "10.20.10.0/24" "10.10.0.26" 2004;
          sitea_mgmt_downstream_dns_v6 =
            hasRoute siteaMgmtRoutes "fd42:dead:beef:0010:0000:0000:0000:0000/64" "fd42:dead:beef:1000:0:0:0:1a" 2004;
          sitea_dns_udp_rule =
            lib.hasInfix "iifname \"downstr-client\" oifname \"downstream-mgmt\" meta l4proto udp udp dport { 53 } accept comment \"allow-sitea-tenants-to-mgmt-dns\"" siteaPolicyRules;
          sitea_dns_tcp_rule =
            lib.hasInfix "iifname \"downstr-client\" oifname \"downstream-mgmt\" meta l4proto tcp tcp dport { 53 } accept comment \"allow-sitea-tenants-to-mgmt-dns\"" siteaPolicyRules;
          sitec_client_to_dmz_dns_v4 =
            hasRoute sitecClientRoutes "10.90.20.0/24" "10.80.0.6" 2002;
          sitec_client_to_dmz_dns_v6 =
            hasRoute sitecClientRoutes "fd42:dead:cafe:0020:0000:0000:0000:0000/64" "fd42:dead:cafe:1000:0:0:0:6" 2002;
        };
      in
      {
        ok = builtins.all (name: checks.${name}) (builtins.attrNames checks);
        failed = builtins.filter (name: !(checks.${name})) (builtins.attrNames checks);
        inherit checks;
      }
    '

assert_json_checks_ok dns-service-policy-routes "${result_json}"

echo "PASS dns-service-policy-routes"
