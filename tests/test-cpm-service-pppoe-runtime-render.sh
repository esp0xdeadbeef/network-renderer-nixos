#!/usr/bin/env bash
# GAMP-ID: FS-800-HDS-030-SDS-010-SMS-010 FS-800-HDS-010-SDS-020-SMS-020
# GAMP-SCOPE: software-module-test
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${repo_root}/tests/lib/test-common.sh"

result_json="$(mktemp)"
eval_stderr="$(mktemp)"
negative_stderr="$(mktemp)"
trap 'rm -f "${result_json}" "${eval_stderr}" "${negative_stderr}"' EXIT

nix_eval_json_or_fail \
  cpm-service-pppoe-runtime-render \
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
        clientService = {
          client = {
            interface = "provider-handoff";
            runtimeInterface = "ppp0";
            inherit credentials;
            defaultRoute = true;
            mtu = 1492;
            usePeerDns = true;
          };
        };
        serverService = {
          server = {
            interface = "provider-handoff";
            providerAddress = "203.0.113.5";
            customerAddress = "203.0.113.4";
            inherit credentials;
            implementation = "rp-pppoe";
            maxSessions = 32;
            mtu = 1492;
          };
        };
        peerDnsHelper = import (repoPath + "/s88/ControlModule/render/containers/module/pppoe/client-peer-dns.nix") {
          inherit lib pkgs;
          peerName = "s88-pppoe-client-provider-handoff";
          scriptSuffix = "provider-handoff";
          usePeerDns = true;
        };
        runtimeInterfaceCommon = import (repoPath + "/s88/Unit/mapping/runtime-targets/interfaces/common.nix") {
          inherit lib;
        };
        hostBridgeIdentity = import (repoPath + "/s88/Unit/mapping/runtime-targets/interfaces/host-bridge.nix") {
          inherit lib;
          common = runtimeInterfaceCommon;
        };
        pppoeVeths = (import (repoPath + "/s88/ControlModule/mapping/container-runtime/interfaces/veths.nix") {
          inherit lib;
          lookup.sortedAttrNames = attrs: builtins.sort builtins.lessThan (builtins.attrNames attrs);
        }).vethsForInterfaces {
          provider-handoff = {
            sourceKind = "pppoe-handoff";
            containerInterfaceName = "ens20";
            hostVethName = "host-ens20";
            renderedHostBridgeName = "br-pppoe";
            usePrimaryHostBridge = false;
          };
          ppp0 = {
            sourceKind = "pppoe-session";
            containerInterfaceName = "ppp0";
            hostVethName = "host-ppp0";
            renderedHostBridgeName = "br-pppoe";
            usePrimaryHostBridge = false;
          };
        };
        renameModule = import (repoPath + "/s88/ControlModule/render/containers/module/interface-renames.nix") {
          inherit lib pkgs;
          renderedModel.interfaces = {
            provider-handoff = {
              sourceKind = "pppoe-handoff";
              hostVethName = "nixc-handoff";
              containerInterfaceName = "ens20";
            };
            ppp0 = {
              sourceKind = "pppoe-session";
              hostVethName = "nixc-ppp0";
              containerInterfaceName = "ppp0";
              backingRef.kind = "pppoe-session";
            };
          };
        };
        renameEval = lib.nixosSystem {
          inherit system;
          modules = [ renameModule.config ];
        };
        renameScript = renameEval.config.systemd.services.s88-rename-interfaces.script;
        pppoeServiceInterfaceName = "p2p-nixos-core-testnet-host-isp-nixos-provider-handoff-access-a";
        pppoeClientBridgeIdentity = hostBridgeIdentity.hostBridgeIdentityForInterface {
          unitName = "nixos-core-testnet-host-isp";
          ifName = pppoeServiceInterfaceName;
          iface = {
            sourceKind = "pppoe-handoff";
            backingRef = {
              kind = "service-interface";
              id = "service-interface::nixos-core-testnet-host-isp::${pppoeServiceInterfaceName}";
              name = pppoeServiceInterfaceName;
              service = "pppoe";
              serviceRole = "client";
            };
          };
        };
        pppoeProviderBridgeIdentity = hostBridgeIdentity.hostBridgeIdentityForInterface {
          unitName = "nixos-provider-handoff-access-a";
          ifName = pppoeServiceInterfaceName;
          iface = {
            sourceKind = "pppoe-handoff";
            backingRef = {
              kind = "service-interface";
              id = "service-interface::nixos-provider-handoff-access-a::${pppoeServiceInterfaceName}";
              name = pppoeServiceInterfaceName;
              service = "pppoe";
              serviceRole = "server";
            };
          };
        };
        clientModule = import (repoPath + "/s88/ControlModule/render/containers/module/pppoe.nix") {
          inherit lib pkgs;
          renderedModel = {
            unitName = "nixos-core-testnet-host-isp";
            interfaces.provider-handoff.containerInterfaceName = "ens20";
            services.pppoe = clientService;
          };
        };
        clientEval = lib.nixosSystem {
          inherit system;
          modules = [ clientModule.config ];
        };
        serverModule = import (repoPath + "/s88/ControlModule/render/containers/module/pppoe.nix") {
          inherit lib pkgs;
          renderedModel = {
            unitName = "nixos-provider-handoff-access-a";
            interfaces.provider-handoff.containerInterfaceName = "ens20";
            services.pppoe = serverService;
          };
        };
        serverEval = lib.nixosSystem {
          inherit system;
          modules = [ serverModule.config ];
        };
        vlanPppoeUplinks.provider = {
          mode = "pppoe";
          vlan = 6;
          bridge = "br-wan6";
          ipv4.method = "pppoe";
          ipv6.method = "pppoe";
        };
        vlanPppoeRenderedModel = {
          unitName = "prod-core";
          interfaces.provider-handoff = {
            containerInterfaceName = "wan";
            sourceKind = "wan";
            assignedUplinkName = "provider";
          };
          services.pppoe = clientService;
        };
        vlanPppoeClientModule = import (repoPath + "/s88/ControlModule/render/containers/module/pppoe.nix") {
          inherit lib pkgs;
          renderedModel = vlanPppoeRenderedModel;
          uplinks = vlanPppoeUplinks;
          wanUplinkName = "provider";
        };
        vlanPppoeClientEval = lib.nixosSystem {
          inherit system;
          modules = [ vlanPppoeClientModule.config ];
        };
        vlanPppoePreStart =
          vlanPppoeClientEval.config.systemd.services."pppd-s88-pppoe-client-provider-handoff".preStart;
        vlanPppoeBridge = import (repoPath + "/s88/ControlModule/render/container-networks/pppoe-vlan-bridge.nix") {
          inherit lib;
          interfaces.provider-handoff = vlanPppoeRenderedModel.interfaces.provider-handoff // {
            _s88PppoeOwned = true;
          };
          interfaceNames = [ "provider-handoff" ];
          renderedInterfaceNames.provider-handoff = "wan";
          uplinks = vlanPppoeUplinks;
          wanUplinkName = "provider";
        };
        mkAssemblyFor =
          pppoeService:
          import (repoPath + "/s88/ControlModule/mapping/container-runtime/model/container-assembly.nix") {
            inherit lib;
            naming = {
              emittedUnitNameForUnit = unitName: unitName;
              containerNameForUnit = unitName: unitName;
            };
            interfaces = {
              normalizedInterfacesForUnit = { unitName, containerName, interfaces }:
                builtins.mapAttrs (_: iface: iface // { containerInterfaceName = iface.containerInterfaceName or iface.interface.name or "ens20"; sourceKind = "lan"; }) interfaces;
              vethsForInterfaces = _: { };
            };
            lookup = {
              deploymentHostName = "s-router-nixos";
              siteData = { };
              inventorySiteData = { };
              hostContext = { };
              sortedAttrNames = attrs: builtins.sort builtins.lessThan (builtins.attrNames attrs);
              runtimeTargetForUnit = unitName: {
                logicalNode = {
                  enterprise = "esp0xdeadbeef";
                  site = "site-a";
                  name = unitName;
                };
                services.pppoe = pppoeService;
                effectiveRuntimeRealization.interfaces.provider-handoff.containerInterfaceName = "ens20";
              };
              roleForUnit = _: "core";
              roleConfigForUnit = _: { };
              containerConfigForUnit = _: { };
            };
          };
        clientRuntime = (mkAssemblyFor clientService).mkContainerRuntime "nixos-core-testnet-host-isp";
        serverRuntime = (mkAssemblyFor serverService).mkContainerRuntime "nixos-provider-handoff-access-a";
        clientServices = clientEval.config.systemd.services;
        clientTimers = clientEval.config.systemd.timers;
        clientPeers = clientEval.config.services.pppd.peers;
        clientPreStart = clientServices."pppd-s88-pppoe-client-provider-handoff".preStart;
        clientServiceUnit = clientServices."pppd-s88-pppoe-client-provider-handoff";
        clientStarterUnit = clientServices."s88-start-s88-pppoe-client-provider-handoff";
        clientStarterTimerUnit = clientTimers."s88-start-s88-pppoe-client-provider-handoff";
        clientPeerConfig = clientPeers."s88-pppoe-client-provider-handoff".config;
        serverServices = serverEval.config.systemd.services;
        serverScript = serverServices.s88-pppoe-server.script;
        serverUnit = serverServices.s88-pppoe-server;
        serverToolsText = serverEval.config.environment.etc."s88/pppoe-tools".text;
        checks = {
          client_pppd_enabled = clientEval.config.services.pppd.enable == true;
          client_peer_emitted = clientPeers ? "s88-pppoe-client-provider-handoff";
          client_peer_autostarts =
            (clientPeers."s88-pppoe-client-provider-handoff".enable or false) == true
            && (clientPeers."s88-pppoe-client-provider-handoff".autostart or true) == false;
          client_service_emitted = clientServices ? "pppd-s88-pppoe-client-provider-handoff";
          client_service_not_directly_wanted_by_multi_user =
            !(builtins.elem "multi-user.target" (clientServiceUnit.wantedBy or [ ]));
          client_starter_service_emitted =
            clientServices ? "s88-start-s88-pppoe-client-provider-handoff";
          client_starter_wanted_by_multi_user =
            builtins.elem "multi-user.target" (clientStarterUnit.wantedBy or [ ]);
          client_starter_can_be_rerun_by_timer =
            (clientStarterUnit.serviceConfig.RemainAfterExit or false) == false;
          client_starter_timer_emitted =
            clientTimers ? "s88-start-s88-pppoe-client-provider-handoff";
          client_starter_timer_wanted_by_timers_target =
            builtins.elem "timers.target" (clientStarterTimerUnit.wantedBy or [ ]);
          client_starter_timer_delays_until_container_post_start_can_attach_veths =
            (clientStarterTimerUnit.timerConfig.OnBootSec or null) == "10s"
            && (clientStarterTimerUnit.timerConfig.Unit or null)
              == "s88-start-s88-pppoe-client-provider-handoff.service";
          client_starter_waits_for_network_online =
            builtins.elem "network-online.target" (clientStarterUnit.after or [ ])
            && builtins.elem "network-online.target" (clientStarterUnit.wants or [ ]);
          client_starter_orders_after_interface_rename =
            builtins.elem "s88-rename-interfaces.service" (clientStarterUnit.after or [ ]);
          client_starter_starts_pppd_unit =
            (clientStarterUnit.serviceConfig.ExecStart or null)
              == "${pkgs.systemd}/bin/systemctl --no-block start pppd-s88-pppoe-client-provider-handoff.service";
          client_starter_does_not_block_container_readiness =
            builtins.match ".* --no-block start .*" (clientStarterUnit.serviceConfig.ExecStart or "") != null;
          client_pppd_unit_does_not_wait_for_session_readiness =
            (clientServiceUnit.serviceConfig.Type or null) == "simple";
          client_service_avoids_network_online_cycle =
            !(builtins.elem "network-online.target" (clientServiceUnit.after or [ ]))
            && !(builtins.elem "network-online.target" (clientServiceUnit.wants or [ ]));
          client_service_keeps_pppd_before_network =
            builtins.elem "network.target" (clientServiceUnit.before or [ ]);
          client_service_restarts =
            (clientServiceUnit.serviceConfig.Restart or null) == "always";
          client_handoff_interface_brought_up =
            builtins.match ".*ip link set ens20 up.*" clientPreStart != null;
          client_uses_pppoe_plugin = builtins.match ".*plugin pppoe[.]so.*nic-ens20.*" clientPreStart != null;
          client_session_options_set_runtime_interface =
            builtins.match ".*ifname ppp0.*" clientPreStart != null;
          client_session_options_install_default_route =
            builtins.match ".*defaultroute.*replacedefaultroute.*" clientPreStart != null;
          client_session_options_enable_ipv6cp =
            builtins.match ".*[+]ipv6.*ipv6cp-accept-local.*ipv6cp-accept-remote.*" clientPreStart != null;
          client_uses_exact_username_path =
            builtins.match ".*cat /run/secrets/provider-access-pppoe-username.*" clientPreStart != null;
          client_uses_exact_password_path =
            builtins.match ".*cat /run/secrets/provider-access-pppoe-password.*" clientPreStart != null;
          client_does_not_inline_secret_values =
            builtins.match ".*[/]bin[/]printf.*" clientPreStart == null;
          client_credential_verifies_content_nonempty =
            builtins.match ".*test -s.*cat.*" clientPreStart != null;
          client_credential_empty_produces_diagnostic =
            builtins.match ".*credential file is empty.*" clientPreStart != null;
          client_does_not_invent_hat_or_sat_secret_names =
            builtins.match ".*hat-pppoe.*" clientPreStart == null
            && builtins.match ".*sat-pppoe.*" clientPreStart == null;
          client_peer_uses_options_file = builtins.match ".*file /run/pppd/s88-pppoe-client-provider-handoff[.]options.*" clientPeerConfig != null;
          client_peer_dns_keeps_hardened_unit =
            (clientServiceUnit.serviceConfig.ProtectSystem or null) == "strict"
            && (clientServiceUnit.serviceConfig.ReadWritePaths or null) == null;
          client_peer_dns_does_not_write_etc =
            builtins.match ".*usepeerdns.*noresolvconf.*" clientPreStart != null;
          client_peer_dns_prestart_has_no_etc_resolv =
            builtins.match ".*[/]etc[/]ppp[/]resolv[.]conf.*" clientPreStart == null;
          client_peer_dns_helper_has_no_etc_resolv =
            builtins.match ".*[/]etc[/]ppp[/]resolv[.]conf.*" peerDnsHelper.ipUpBlock == null;
          client_peer_dns_helper_writes_runtime_resolv =
            builtins.match ".*[/]run[/]pppd[/]s88-pppoe-client-provider-handoff[.]resolv[.]conf.*" peerDnsHelper.ipUpBlock != null;
          client_peer_dns_writes_runtime_resolv =
            builtins.match ".*ip-up-script /nix/store/[^[:space:]]+s88-pppoe-ip-up-provider-handoff.*" clientPreStart != null;
          client_peer_dns_cleans_runtime_resolv =
            builtins.match ".*ip-down-script /nix/store/[^[:space:]]+s88-pppoe-ip-down-provider-handoff.*" clientPreStart != null;
          pppoe_session_veth_not_emitted =
            !(pppoeVeths ? "host-ppp0");
          pppoe_handoff_veth_still_emitted =
            (pppoeVeths."host-ens20".hostBridge or null) == "br-pppoe";
          pppoe_session_rename_not_emitted =
            builtins.match ".*ppp0.*" renameScript == null
            && builtins.match ".*nixc-ppp0.*" renameScript == null;
          pppoe_handoff_rename_still_emitted =
            builtins.match ".*ens20.*" renameScript != null
            && builtins.match ".*nixc-handoff.*" renameScript != null;
          pppoe_handoff_endpoints_share_bridge_identity =
            pppoeClientBridgeIdentity == pppoeProviderBridgeIdentity;
          client_runtime_binds_ppp_device =
            (clientRuntime.bindMounts."/dev/ppp".hostPath or null) == "/dev/ppp"
            && clientRuntime.bindMounts."/dev/ppp".isReadOnly == false;
          client_runtime_binds_exact_username_path =
            (clientRuntime.bindMounts."/run/secrets/provider-access-pppoe-username".hostPath or null)
              == "/run/secrets/provider-access-pppoe-username"
            && clientRuntime.bindMounts."/run/secrets/provider-access-pppoe-username".isReadOnly == true;
          client_runtime_binds_exact_password_path =
            (clientRuntime.bindMounts."/run/secrets/provider-access-pppoe-password".hostPath or null)
              == "/run/secrets/provider-access-pppoe-password"
            && clientRuntime.bindMounts."/run/secrets/provider-access-pppoe-password".isReadOnly == true;
          client_runtime_allows_ppp_device =
            builtins.elem { node = "/dev/ppp"; modifier = "rw"; } clientRuntime.allowedDevices;
          server_runtime_binds_ppp_device =
            (serverRuntime.bindMounts."/dev/ppp".hostPath or null) == "/dev/ppp"
            && serverRuntime.bindMounts."/dev/ppp".isReadOnly == false;
          server_runtime_binds_exact_username_path =
            (serverRuntime.bindMounts."/run/secrets/provider-access-pppoe-username".hostPath or null)
              == "/run/secrets/provider-access-pppoe-username"
            && serverRuntime.bindMounts."/run/secrets/provider-access-pppoe-username".isReadOnly == true;
          server_runtime_binds_exact_password_path =
            (serverRuntime.bindMounts."/run/secrets/provider-access-pppoe-password".hostPath or null)
              == "/run/secrets/provider-access-pppoe-password"
            && serverRuntime.bindMounts."/run/secrets/provider-access-pppoe-password".isReadOnly == true;
          server_runtime_allows_ppp_device =
            builtins.elem { node = "/dev/ppp"; modifier = "rw"; } serverRuntime.allowedDevices;
          server_service_emitted = serverServices ? s88-pppoe-server;
          server_service_wanted_by_multi_user =
            builtins.elem "multi-user.target" (serverUnit.wantedBy or [ ]);
          server_service_waits_for_handoff_network =
            builtins.elem "network-online.target" (serverUnit.after or [ ])
            && builtins.elem "network-online.target" (serverUnit.wants or [ ]);
          server_service_restarts =
            (serverUnit.serviceConfig.Restart or null) == "always"
            && (serverUnit.serviceConfig.RestartSec or null) == 2;
          server_service_tracks_forked_daemon =
            (serverUnit.serviceConfig.Type or null) == "forking"
            && (serverUnit.serviceConfig.PIDFile or null) == "/run/s88-pppoe-server/pppoe-server.pid"
            && (serverUnit.serviceConfig.RuntimeDirectory or null) == "s88-pppoe-server";
          server_handoff_interface_brought_up =
            builtins.match ".*ip link set ens20 up.*" serverScript != null;
          server_uses_pppoe_server = builtins.match ".*pppoe-server.*-I ens20.*" serverScript != null;
          server_uses_exact_username_path =
            builtins.match ".*cat /run/secrets/provider-access-pppoe-username.*" serverScript != null;
          server_uses_exact_password_path =
            builtins.match ".*cat /run/secrets/provider-access-pppoe-password.*" serverScript != null;
          server_does_not_inline_secret_values =
            builtins.match ".*[/]bin[/]printf.*" serverScript == null;
          server_credential_verifies_content_nonempty =
            builtins.match ".*test -s.*cat.*" serverScript != null;
          server_credential_empty_produces_diagnostic =
            builtins.match ".*credential file is empty.*" serverScript != null;
          server_does_not_invent_hat_or_sat_secret_names =
            builtins.match ".*hat-pppoe.*" serverScript == null
            && builtins.match ".*sat-pppoe.*" serverScript == null;
          server_uses_pidfile = builtins.match ".*-X '/run/s88-pppoe-server/pppoe-server[.]pid'.*" serverScript != null;
          server_uses_session_addresses =
            builtins.match ".*203[.]0[.]113[.]5.*203[.]0[.]113[.]4.*" serverScript != null;
          server_exposes_tools = serverEval.config.environment.etc ? "s88/pppoe-tools";
          server_debug_tools_include_pppoe_sniff =
            builtins.match ".*pppoe-sniff=.*[/]bin[/]pppoe-sniff.*" serverToolsText != null;
          server_debug_tools_include_pppd =
            builtins.match ".*pppd=.*[/]bin[/]pppd.*" serverToolsText != null;
          vlan_pppoe_renders_container_vlan_netdev =
            (vlanPppoeBridge.netdevs."10-wan.6".netdevConfig.Name or null) == "wan.6"
            && (vlanPppoeBridge.netdevs."10-wan.6".netdevConfig.Kind or null) == "vlan"
            && (vlanPppoeBridge.netdevs."10-wan.6".vlanConfig.Id or null) == 6;
          vlan_pppoe_renders_container_bridge_netdev =
            (vlanPppoeBridge.netdevs."20-br-wan6".netdevConfig.Name or null) == "br-wan6"
            && (vlanPppoeBridge.netdevs."20-br-wan6".netdevConfig.Kind or null) == "bridge";
          vlan_pppoe_parent_interface_carries_vlan_only =
            (vlanPppoeBridge.networks."05-wan".networkConfig.DHCP or null) == "no"
            && (vlanPppoeBridge.networks."05-wan".networkConfig.VLAN or [ ]) == [ "wan.6" ];
          vlan_pppoe_vlan_subinterface_attaches_to_bridge =
            (vlanPppoeBridge.networks."50-wan.6".networkConfig.Bridge or null) == "br-wan6";
          vlan_pppoe_bridge_has_no_dhcp_fallback =
            (vlanPppoeBridge.networks."60-br-wan6".networkConfig.DHCP or null) == "no";
          vlan_pppoe_client_uses_bridge_as_pppoe_nic =
            builtins.match ".*plugin pppoe[.]so.*nic-br-wan6.*" vlanPppoePreStart != null;
          vlan_pppoe_client_does_not_use_raw_lower_nic =
            builtins.match ".*plugin pppoe[.]so.*nic-wan.*" vlanPppoePreStart == null;
        };
      in
      {
        ok = builtins.all (name: checks.${name}) (builtins.attrNames checks);
        failed = builtins.filter (name: !(checks.${name})) (builtins.attrNames checks);
        inherit checks;
      }
    '

assert_json_checks_ok cpm-service-pppoe-runtime-render "${result_json}"

run_negative_eval() {
  local label="$1"
  local expr="$2"
  local expected="$3"

  if env REPO_ROOT="${repo_root}" NEGATIVE_EXPR="${expr}" \
    nix eval \
      --extra-experimental-features 'nix-command flakes' \
      --impure --expr '
        let
          repoPath = builtins.getEnv "REPO_ROOT";
          flake = builtins.getFlake ("path:" + repoPath);
          lib = flake.inputs.nixpkgs.lib;
          system = builtins.currentSystem;
          pkgs = import flake.inputs.nixpkgs { inherit system; };
          module = import (repoPath + "/s88/ControlModule/render/containers/module/pppoe.nix") {
            inherit lib pkgs;
            renderedModel = builtins.fromJSON (builtins.getEnv "NEGATIVE_EXPR");
          };
          eval = lib.nixosSystem {
            inherit system;
            modules = [ module.config ];
          };
        in
          eval.config.system.build.toplevel.drvPath
      ' >/dev/null 2>"${negative_stderr}"; then
    echo "FAIL ${label}: invalid PPPoE renderer input evaluated successfully" >&2
    exit 1
  fi

  if ! rg -q "${expected}" "${negative_stderr}"; then
    echo "FAIL ${label}: missing expected diagnostic ${expected}" >&2
    cat "${negative_stderr}" >&2
    exit 1
  fi
}

run_negative_eval \
  cpm-service-pppoe-missing-client-interface \
  '{"unitName":"bad-client","interfaces":{"provider-handoff":{"containerInterfaceName":"ens20"}},"services":{"pppoe":{"client":{"interface":"missing-handoff","runtimeInterface":"ppp0","credentials":{"labOnly":true,"usernameFile":"/run/secrets/provider-access-pppoe-username","passwordFile":"/run/secrets/provider-access-pppoe-password"},"defaultRoute":true}}}}' \
  "services.pppoe.client.interface to name a rendered interface"

run_negative_eval \
  cpm-service-pppoe-missing-server-interface \
  '{"unitName":"bad-server","interfaces":{"provider-handoff":{"containerInterfaceName":"ens20"}},"services":{"pppoe":{"server":{"interface":"missing-handoff","providerAddress":"203.0.113.5","customerAddress":"203.0.113.4","credentials":{"labOnly":true,"usernameFile":"/run/secrets/provider-access-pppoe-username","passwordFile":"/run/secrets/provider-access-pppoe-password"},"implementation":"rp-pppoe"}}}}' \
  "services.pppoe.server.interface to name a rendered interface"

run_negative_eval \
  cpm-service-pppoe-unsupported-implementation \
  '{"unitName":"bad-server","interfaces":{"provider-handoff":{"containerInterfaceName":"ens20"}},"services":{"pppoe":{"server":{"interface":"provider-handoff","providerAddress":"203.0.113.5","customerAddress":"203.0.113.4","credentials":{"labOnly":true,"usernameFile":"/run/secrets/provider-access-pppoe-username","passwordFile":"/run/secrets/provider-access-pppoe-password"},"implementation":"accel-ppp"}}}}' \
  "supported implementation"

run_negative_eval \
  cpm-service-pppoe-missing-client-secret-path \
  '{"unitName":"bad-client-secret","interfaces":{"provider-handoff":{"containerInterfaceName":"ens20"}},"services":{"pppoe":{"client":{"interface":"provider-handoff","runtimeInterface":"ppp0","credentials":{"labOnly":true,"usernameFile":"/run/secrets/provider-access-pppoe-username"},"defaultRoute":true}}}}' \
  "credentials.usernameFile and credentials.passwordFile paths"

run_negative_eval \
  cpm-service-pppoe-inline-client-secret \
  '{"unitName":"bad-client-inline-secret","interfaces":{"provider-handoff":{"containerInterfaceName":"ens20"}},"services":{"pppoe":{"client":{"interface":"provider-handoff","runtimeInterface":"ppp0","credentials":{"labOnly":true,"username":"hat-pppoe","password":"hat-pppoe"},"defaultRoute":true}}}}' \
  "no inline username/password values"

run_negative_eval \
  cpm-service-pppoe-missing-server-secret-path \
  '{"unitName":"bad-server-secret","interfaces":{"provider-handoff":{"containerInterfaceName":"ens20"}},"services":{"pppoe":{"server":{"interface":"provider-handoff","providerAddress":"203.0.113.5","customerAddress":"203.0.113.4","credentials":{"labOnly":true,"usernameFile":"/run/secrets/provider-access-pppoe-username"},"implementation":"rp-pppoe"}}}}' \
  "credentials.usernameFile and credentials.passwordFile paths"

run_negative_eval \
  cpm-service-pppoe-inline-server-secret \
  '{"unitName":"bad-server-inline-secret","interfaces":{"provider-handoff":{"containerInterfaceName":"ens20"}},"services":{"pppoe":{"server":{"interface":"provider-handoff","providerAddress":"203.0.113.5","customerAddress":"203.0.113.4","credentials":{"labOnly":true,"username":"hat-pppoe","password":"hat-pppoe"},"implementation":"rp-pppoe"}}}}' \
  "no inline username/password values"

echo "PASS cpm-service-pppoe-runtime-render"
