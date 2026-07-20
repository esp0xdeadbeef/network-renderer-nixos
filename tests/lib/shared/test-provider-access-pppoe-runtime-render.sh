#!/usr/bin/env bash
# GAMP-ID: FS-800-HDS-030-SDS-010-SMS-010 FS-800-HDS-010-SDS-020-SMS-020
# GAMP-SCOPE: software-module-test
set -euo pipefail

repo_root="${SMS_TEST_REPO_ROOT:-$(git -C "$(dirname "${BASH_SOURCE[0]}")" rev-parse --show-toplevel)}"
source "${repo_root}/tests/lib/test-common.sh"

result_json="$(mktemp)"
eval_stderr="$(mktemp)"
trap 'rm -f "${result_json}" "${eval_stderr}"' EXIT

nix_eval_json_or_fail \
  provider-access-pppoe-runtime-render \
  "${result_json}" \
  "${eval_stderr}" \
  env REPO_ROOT="${repo_root}" \
    nix eval \
    --extra-experimental-features 'nix-command flakes' \
    --impure --json --expr '
      let
        repoPath = builtins.getEnv "REPO_ROOT";
        flake = builtins.getFlake ("path:" + repoPath);
        lib = flake.inputs.nixpkgs.lib;
        system = builtins.currentSystem;
        pkgs = import flake.inputs.nixpkgs { inherit system; };
        credentials = {
          labOnly = true;
          usernameFile = "/run/secrets/provider-access-pppoe-username";
          passwordFile = "/run/secrets/provider-access-pppoe-password";
        };
        dynamicWanInterface = {
          containerInterfaceName = "ens20";
          sourceKind = "wan";
          policyRoutingAllocation = {
            source = "control-plane-model";
            tableId = 1002;
            tableRulePriority = 1002;
            mainSuppressPriority = 11002;
            dynamicRulePriority = 10002;
          };
          dynamicAddressing = {
            ipv4 = {
              enable = true;
              method = "dhcp";
            };
            ipv6 = {
              enable = true;
              method = "slaac";
              acceptRA = true;
            };
          };
        };
        renderContainer =
          services:
          let
            module = import (repoPath + "/s88/ControlModule/render/containers/module.nix") {
              inherit lib;
              containerName = "nixos-pppoe-runtime";
              renderedModel = {
                unitName = "nixos-pppoe-runtime";
                interfaces.provider-handoff = dynamicWanInterface;
                inherit services;
              };
              firewallArg = { enable = false; };
              alarmModel = { };
              uplinks = { };
              wanUplinkName = null;
            };
            eval = lib.nixosSystem {
              inherit system;
              modules = [ module ];
            };
          in
            eval.config;
        clientConfig = renderContainer {
          pppoe.client = {
            interface = "provider-handoff";
            runtimeInterface = "ppp0";
            inherit credentials;
            defaultRoute = true;
          };
        };
        serverConfig = renderContainer {
          pppoe.server = {
            interface = "provider-handoff";
            providerAddress = "203.0.113.5";
            customerAddress = "203.0.113.4";
            inherit credentials;
            implementation = "rp-pppoe";
          };
        };
        nonPppoeConfig = renderContainer { };
        legacySideChannel = side: {
          backend = "nixos";
          mode = "pppoe";
          handoff = {
            bridge = "br-nix-pppoe";
            mtu = 1492;
          };
          pppoe.${side} =
            if side == "server" then
              {
                side = "provider";
                implementation = "rp-pppoe";
                node = "provider-only";
                handoffBridge = "br-nix-pppoe";
              }
            else
              {
                coreNode = "customer-only";
                coreInterface = "provider-handoff";
                runtimeInterface = "ppp0";
                handoffBridge = "br-nix-pppoe";
              };
        };
        sideChannelConfig =
          side:
          let
            module = import (repoPath + "/s88/ControlModule/render/containers/module.nix") {
              inherit lib;
              containerName = "nixos-side-channel-${side}";
              renderedModel = {
                unitName = "nixos-side-channel-${side}";
                interfaces.provider-handoff.containerInterfaceName = "ens20";
                site.providerAccess.pppoeNixos = legacySideChannel side;
              };
              firewallArg = { enable = false; };
              alarmModel = { };
              uplinks = { };
              wanUplinkName = null;
            };
            eval = lib.nixosSystem {
              inherit system;
              modules = [ module ];
            };
          in
            eval.config;
        clientNetwork = clientConfig.systemd.network.networks."10-ens20".networkConfig;
        serverNetwork = serverConfig.systemd.network.networks."10-ens20".networkConfig;
        nonPppoeNetwork = nonPppoeConfig.systemd.network.networks."10-ens20".networkConfig;
        clientDhcpV4 = clientConfig.systemd.network.networks."10-ens20".dhcpV4Config or { };
        serverDhcpV4 = serverConfig.systemd.network.networks."10-ens20".dhcpV4Config or { };
        nonPppoeDhcpV4 = nonPppoeConfig.systemd.network.networks."10-ens20".dhcpV4Config or { };
        sideChannelClientOnly = sideChannelConfig "client";
        sideChannelServerOnly = sideChannelConfig "server";
        checks = {
          client_pppoe_service_rendered =
            clientConfig.services.pppd.peers ? "s88-pppoe-client-provider-handoff";
          client_pppoe_owned_interface_suppresses_dhcp = clientNetwork.DHCP == "no";
          client_pppoe_owned_interface_suppresses_slaac =
            (clientNetwork.IPv6AcceptRA or false) == false
            && clientNetwork.LinkLocalAddressing == "no";
          server_pppoe_service_rendered =
            serverConfig.systemd.services ? s88-pppoe-server;
          server_pppoe_owned_interface_suppresses_dhcp = serverNetwork.DHCP == "no";
          server_pppoe_owned_interface_suppresses_slaac =
            (serverNetwork.IPv6AcceptRA or false) == false
            && serverNetwork.LinkLocalAddressing == "no";
          non_pppoe_wan_dynamic_fallback_still_renders =
            nonPppoeNetwork.DHCP == "ipv4"
            && (nonPppoeNetwork.IPv6AcceptRA or false) == true
            && nonPppoeNetwork.LinkLocalAddressing == "ipv6";
          non_pppoe_wan_dhcp_routes_use_cpm_policy_table =
            (nonPppoeDhcpV4.RouteTable or null) == 1002;
          client_pppoe_owned_interface_does_not_route_dhcp =
            !(clientDhcpV4 ? RouteTable);
          server_pppoe_owned_interface_does_not_route_dhcp =
            !(serverDhcpV4 ? RouteTable);
          legacy_provider_only_side_channel_does_not_render_server =
            !(sideChannelServerOnly.systemd.services ? s88-pppoe-server)
            && !(sideChannelServerOnly.environment.etc ? "s88/pppoe-tools");
          legacy_customer_only_side_channel_does_not_render_client =
            !(sideChannelClientOnly.services.pppd.peers ? "s88-pppoe-client-provider-handoff");
        };
      in
      {
        ok = builtins.all (name: checks.${name}) (builtins.attrNames checks);
        failed = builtins.filter (name: !(checks.${name})) (builtins.attrNames checks);
        inherit checks;
      }
    '

assert_json_checks_ok provider-access-pppoe-runtime-render "${result_json}"

echo "PASS provider-access-pppoe-runtime-render"
