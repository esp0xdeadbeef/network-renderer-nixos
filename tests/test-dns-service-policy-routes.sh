#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${repo_root}/tests/lib/test-common.sh"

example_root="$(flake_input_path network-labs)/examples/s-router-overlay-dns-lane-policy"
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
        hasRouteNoTable = routes: destination: gateway:
          builtins.any
            (route:
              (route.Destination or null) == destination
              && (route.Gateway or null) == gateway
              && !(route ? Table))
            routes;
        hasRule = rules: incomingInterface: table:
          builtins.any
            (rule:
              (rule.IncomingInterface or null) == incomingInterface
              && (rule.Table or null) == table)
            rules;
        policyTableFor = networks: networkName:
          let
            rules = networks.${networkName}.routingPolicyRules or [ ];
            tableRules =
              builtins.filter
                (rule: builtins.isInt (rule.Table or null) && (rule.Table or null) != 254)
                rules;
          in
            if tableRules == [ ] then null else (builtins.head tableRules).Table;
        hasPolicyRoute = networks: destination: gateway: table:
          table != null && hasRouteAnyNetwork networks destination gateway table;
        hasMainOrPolicyRoute = networks: destination: gateway: table:
          hasPolicyRoute networks destination gateway table
          || builtins.any
            (networkName: hasRouteNoTable (networks.${networkName}.routes or [ ]) destination gateway)
            (builtins.attrNames networks);
        hasAllPolicyRoutes = networks: routes: table:
          table != null
          && builtins.all
            (route: hasRouteAnyNetwork networks route.destination route.gateway table)
            routes;
        missingRoute = routes: destination: gateway: table:
          !(hasRoute routes destination gateway table);
        hasRouteAnyNetwork = networks: destination: gateway: table:
          builtins.any
            (networkName: hasRoute (networks.${networkName}.routes or [ ]) destination gateway table)
            (builtins.attrNames networks);
        branchNetworks = branchCfg.systemd.network.networks;
        branchPolicyRules = branchCfg.networking.nftables.ruleset;
        branchUpstreamNetworks = branchUpstreamCfg.systemd.network.networks;
        siteaUpstreamNetworks = siteaUpstreamCfg.systemd.network.networks;
        siteaPolicyNetworks = siteaPolicyCfg.systemd.network.networks;
        sitecNetworks = sitecCfg.systemd.network.networks;
        siteaPolicyRules = siteaPolicyCfg.networking.nftables.ruleset;
        bUpstreamCoreIngressRoutes =
          (branchUpstreamNetworks."10-pol-branch-ew".routes or [ ])
          ++ (branchUpstreamNetworks."10-pol-hostile-ew".routes or [ ]);
        siteaMgmtRoutes = siteaPolicyNetworks."10-downstream-mgmt".routes or [ ];
        siteaAdminWanReturnRoutes = siteaUpstreamNetworks."10-pol-admin-a".routes or [ ];
        siteaMgmtWanReturnRoutes = siteaUpstreamNetworks."10-pol-mgmt-a".routes or [ ];
        siteaMgmtEastWestReturnRoutes = siteaUpstreamNetworks."10-pol-mgt-ew".routes or [ ];
        branchHostileOverlayRoutes = branchUpstreamNetworks."10-core-nebula".routes or [ ];
        branchHostileWanRoutes = branchUpstreamNetworks."10-core-isp".routes or [ ];
        branchCoreNebulaRules = branchUpstreamNetworks."10-core-nebula".routingPolicyRules or [ ];
        sitecClientRoutes = sitecNetworks."10-downstr-client".routes or [ ];
        branchCoreNebulaTable = policyTableFor branchUpstreamNetworks "10-core-nebula";
        branchBranchEwTable = policyTableFor branchUpstreamNetworks "10-pol-branch-ew";
        branchHostileEwTable = policyTableFor branchUpstreamNetworks "10-pol-hostile-ew";
        siteaCoreNebulaTable = policyTableFor siteaUpstreamNetworks "10-core-nebula";
        siteaCoreATable = policyTableFor siteaUpstreamNetworks "10-core-a";
        siteaCoreBTable = policyTableFor siteaUpstreamNetworks "10-core-b";
        siteaMgmtEwTable = policyTableFor siteaUpstreamNetworks "10-pol-mgt-ew";
        siteaAdminEwTable = policyTableFor siteaUpstreamNetworks "10-pol-adm-ew";
        siteaAdminWanTable = policyTableFor siteaUpstreamNetworks "10-pol-admin-a";
        siteaMgmtWanTable = policyTableFor siteaUpstreamNetworks "10-pol-mgmt-a";
        checks = {
          branch_v4_dns_route =
            hasRouteAnyNetwork branchNetworks "10.20.10.0/24" "10.50.0.13" 2000;
          branch_v6_dns_route =
            hasRouteAnyNetwork branchNetworks "fd42:dead:beef:0010:0000:0000:0000:0000/64" "fd42:dead:feed:1000:0:0:0:d" 2000;
          branch_dns_service_udp_rule =
            lib.hasInfix "iifname \"downstr-branch\" oifname \"up-branch-ew\" meta l4proto udp udp dport { 53 } accept comment \"allow-branch-dns-to-sitea-mgmt-dns\"" branchPolicyRules;
          branch_dns_service_tcp_rule =
            lib.hasInfix "iifname \"downstr-branch\" oifname \"up-branch-ew\" meta l4proto tcp tcp dport { 53 } accept comment \"allow-branch-dns-to-sitea-mgmt-dns\"" branchPolicyRules;
          branch_dns_service_wrong_lane_udp_absent =
            !(lib.hasInfix "iifname \"downstr-branch\" oifname \"up-hostile-ew\" meta l4proto udp udp dport { 53 } accept comment \"allow-branch-dns-to-sitea-mgmt-dns\"" branchPolicyRules);
          branch_dns_service_wrong_lane_tcp_absent =
            !(lib.hasInfix "iifname \"downstr-branch\" oifname \"up-hostile-ew\" meta l4proto tcp tcp dport { 53 } accept comment \"allow-branch-dns-to-sitea-mgmt-dns\"" branchPolicyRules);
          hostile_dns_service_wrong_lane_udp_absent =
            !(lib.hasInfix "iifname \"downstr-hostile\" oifname \"up-branch-ew\" meta l4proto udp udp dport { 53 } accept comment \"allow-hostile-dns-to-sitec-public-dns\"" branchPolicyRules);
          hostile_dns_service_wrong_lane_tcp_absent =
            !(lib.hasInfix "iifname \"downstr-hostile\" oifname \"up-branch-ew\" meta l4proto tcp tcp dport { 53 } accept comment \"allow-hostile-dns-to-sitec-public-dns\"" branchPolicyRules);
          branch_upstream_branch_return =
            hasAllPolicyRoutes branchUpstreamNetworks [
              { destination = "10.60.10.0/24"; gateway = "10.50.0.12"; }
              { destination = "10.50.0.0/31"; gateway = "10.50.0.12"; }
            ] branchCoreNebulaTable;
          branch_upstream_hostile_return =
            hasAllPolicyRoutes branchUpstreamNetworks [
              { destination = "10.70.10.0/24"; gateway = "10.50.0.16"; }
              { destination = "10.50.0.2/31"; gateway = "10.50.0.16"; }
              { destination = "fd42:dead:feed:70::/64"; gateway = "fd42:dead:feed:1000:0:0:0:10"; }
              { destination = "fd42:dead:feed:1000:0:0:0:2/127"; gateway = "fd42:dead:feed:1000:0:0:0:10"; }
            ] branchCoreNebulaTable;
          branch_upstream_core_nebula_ingress_rule =
            hasRule branchCoreNebulaRules "core-nebula" branchCoreNebulaTable;
          branch_upstream_core_nebula_hostile_return =
            hasPolicyRoute branchUpstreamNetworks "10.70.10.0/24" "10.50.0.16" branchCoreNebulaTable;
          branch_upstream_core_nebula_hostile_return_v6 =
            hasPolicyRoute branchUpstreamNetworks "fd42:dead:feed:70::/64" "fd42:dead:feed:1000:0:0:0:10" branchCoreNebulaTable;
          branch_upstream_wrong_v4_absent =
            missingRoute bUpstreamCoreIngressRoutes "10.50.0.0" "10.50.0.16" 2000;
          branch_upstream_wrong_v6_absent =
            missingRoute bUpstreamCoreIngressRoutes "fd42:dead:feed:1000:0:0:0:0" "fd42:dead:feed:1000:0:0:0:10" 2000;
          branch_hostile_sitec_dns_uses_overlay =
            hasPolicyRoute branchUpstreamNetworks "10.90.10.1" "10.50.0.4" branchHostileEwTable;
          branch_hostile_sitec_dns_not_on_wan =
            missingRoute branchHostileWanRoutes "10.90.10.1" "10.50.0.4" 2004;
          sitea_upstream_dns_route =
            hasPolicyRoute siteaUpstreamNetworks "10.20.10.0/24" "10.10.0.48" siteaCoreNebulaTable;
          sitea_upstream_wrong_lane_absent =
            !(hasRouteAnyNetwork siteaUpstreamNetworks "10.20.10.0/24" "10.10.0.30" 2001);
          sitea_mgmt_wan_dns_v4 =
            hasPolicyRoute siteaUpstreamNetworks "10.20.10.0/24" "10.10.0.50" siteaCoreATable;
          sitea_mgmt_wan_p2p_v4 =
            hasPolicyRoute siteaUpstreamNetworks "10.10.0.8/31" "10.10.0.48" siteaCoreNebulaTable;
          sitea_mgmt_wan_dns_v6 =
            hasPolicyRoute siteaUpstreamNetworks "fd42:dead:beef:10::/64" "fd42:dead:beef:1000:0:0:0:32" siteaCoreATable;
          sitea_mgmt_wan_p2p_v6 =
            hasPolicyRoute siteaUpstreamNetworks "fd42:dead:beef:1000:0:0:0:8/127" "fd42:dead:beef:1000:0:0:0:30" siteaCoreNebulaTable;
          sitea_admin_wan_return_v4 =
            hasPolicyRoute siteaUpstreamNetworks "10.20.15.0/24" "10.10.0.30" siteaCoreNebulaTable;
          sitea_admin_wan_return_v6 =
            hasPolicyRoute siteaUpstreamNetworks "fd42:dead:beef:15::/64" "fd42:dead:beef:1000:0:0:0:1e" siteaCoreNebulaTable;
          sitea_mgmt_wan_admin_return_v4_absent =
            missingRoute siteaMgmtWanReturnRoutes "10.20.15.0/24" "10.10.0.50" 2000;
          sitea_mgmt_wan_admin_return_v6_absent =
            missingRoute siteaMgmtWanReturnRoutes "fd42:dead:beef:15::/64" "fd42:dead:beef:1000:0:0:0:32" 2000;
          sitea_mgmt_wan_client_return_v4_absent =
            missingRoute siteaMgmtWanReturnRoutes "10.20.20.0/24" "10.10.0.50" 2000;
          sitea_mgmt_wan_client_return_v6_absent =
            missingRoute siteaMgmtWanReturnRoutes "fd42:dead:beef:20::/64" "fd42:dead:beef:1000:0:0:0:32" 2000;
          sitea_mgmt_ew_branch_p2p_v4 =
            hasMainOrPolicyRoute siteaUpstreamNetworks "10.50.0.0/32" "10.10.0.16" siteaCoreNebulaTable;
          sitea_mgmt_ew_branch_p2p_v6 =
            hasMainOrPolicyRoute siteaUpstreamNetworks "fd42:dead:feed:1000:0:0:0:0/128" "fd42:dead:beef:1000:0:0:0:10" siteaCoreNebulaTable;
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
