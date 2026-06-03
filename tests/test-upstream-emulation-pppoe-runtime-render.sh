#!/usr/bin/env bash
# GAMP-ID: FS-800-HDS-010-SDS-010-SMS-010
# GAMP-SCOPE: software-module-test
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${repo_root}/tests/lib/test-common.sh"

result_json="$(mktemp)"
eval_stderr="$(mktemp)"
trap 'rm -f "${result_json}" "${eval_stderr}"' EXIT

nix_eval_json_or_fail \
  upstream-emulation-pppoe-runtime-render \
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
        row = {
          backend = "nixos";
          mode = "pppoe";
          handoff = {
            bridge = "br-nix-pppoe";
            mtu = 1492;
          };
          pppoe = {
            server = {
              side = "provider";
              implementation = "accel-ppp";
              node = "sat-nixos-pppoe-ac";
              handoffBridge = "br-nix-pppoe";
              credentials = {
                usernameFile = "/run/secrets/sat-pppoe-nixos-username";
                passwordFile = "/run/secrets/sat-pppoe-nixos-password";
              };
              session = {
                providerAddress = "203.0.113.9";
                customerAddress = "203.0.113.10";
                ipv4Prefix = "203.0.113.8/30";
                delegatedAggregate = "2001:db8:800:10::/60";
              };
            };
            client = {
              coreNode = "nixos-router-core-isp-a";
              coreInterface = "pppoe-wan";
              runtimeInterface = "ppp0";
              handoffBridge = "br-nix-pppoe";
              addressDelivery = {
                ipv4 = "pppoe-session-address";
                ipv6 = "pppoe-delegated-prefix";
                wanDhcpFallback = false;
                wanSlaacFallback = false;
              };
            };
          };
        };
        clientModule = import (repoPath + "/s88/ControlModule/render/containers/module/pppoe.nix") {
          inherit lib pkgs;
          renderedModel = {
            unitName = "nixos-router-core-isp-a";
            interfaces.pppoe-wan.containerInterfaceName = "wan-pppoe";
            site.upstreamEmulation.pppoeNixos = row;
          };
        };
        clientEval = flake.inputs.nixpkgs.lib.nixosSystem {
          inherit system;
          modules = [ clientModule.config ];
        };
        serverContainers = import (repoPath + "/s88/ControlModule/render/pppoe-server-containers.nix") {
          inherit lib;
          cpm = {
            control_plane_model.data.esp.nixos.upstreamEmulation.pppoeNixos = row;
          };
          hostName = "s-router-nixos";
          hostPlan.selectedUnits = [ "nixos-router-core-isp-a" ];
        };
        serverEval = flake.inputs.nixpkgs.lib.nixosSystem {
          inherit system;
          modules = [ serverContainers.sat-nixos-pppoe-ac.config ];
        };
        clientServices = clientEval.config.systemd.services;
        clientPeers = clientEval.config.services.pppd.peers;
        serverServices = serverEval.config.systemd.services;
        clientUnit = clientServices."pppd-s88-pppoe-client-pppoe-wan";
        clientPreStart = clientUnit.preStart;
        clientPeerConfig = clientPeers."s88-pppoe-client-pppoe-wan".config;
        serverScript = serverServices.s88-pppoe-server.script;
        checks = {
          client_pppd_enabled = clientEval.config.services.pppd.enable == true;
          client_peer_emitted = clientPeers ? "s88-pppoe-client-pppoe-wan";
          client_peer_uses_runtime_options =
            builtins.match ".*file /run/pppd/s88-pppoe-client-pppoe-wan[.]options.*" clientPeerConfig != null;
          client_service_emitted = clientServices ? "pppd-s88-pppoe-client-pppoe-wan";
          client_uses_native_pppoe_plugin =
            builtins.match ".*plugin pppoe[.]so.*nic-wan-pppoe.*" clientPreStart != null;
          client_uses_pap_like_legacy =
            builtins.match ".*refuse-chap.*refuse-mschap.*refuse-eap.*" clientPreStart != null;
          client_uses_modeled_interface = builtins.match ".*ip link set wan-pppoe up.*" clientPreStart != null;
          client_reads_modeled_secret_files =
            builtins.match ".*sat-pppoe-nixos-username.*sat-pppoe-nixos-password.*" clientPreStart != null;
          server_container_emitted = serverContainers ? sat-nixos-pppoe-ac;
          server_attaches_handoff_bridge = serverContainers.sat-nixos-pppoe-ac.hostBridge == "br-nix-pppoe";
          server_service_emitted = serverServices ? s88-pppoe-server;
          server_uses_pppoe_server = builtins.match ".*pppoe-server.*-I eth0.*" serverScript != null;
          server_exposes_pppoe_sniff =
            (serverEval.config.environment.etc ? "s88/pppoe-tools")
            && builtins.match ".*pppoe-sniff.*" serverEval.config.environment.etc."s88/pppoe-tools".text != null
            && builtins.match ".*pppoe-sniff.*" serverScript != null;
          server_writes_pppd_options =
            builtins.match ".*s88-pppoe-server-options.*require-pap.*refuse-chap.*" serverScript != null;
          server_writes_pap_secrets =
            builtins.match ".*sat-pppoe-nixos-username.*sat-pppoe-nixos-password.*pap-secrets.*" serverScript != null;
          server_uses_explicit_pppd =
            builtins.match ".*-q .*/bin/pppd.*" serverScript != null;
          server_uses_session_addresses =
            builtins.match ".*203[.]0[.]113[.]9.*203[.]0[.]113[.]10.*" serverScript != null;
        };
      in
      {
        ok = builtins.all (name: checks.${name}) (builtins.attrNames checks);
        failed = builtins.filter (name: !(checks.${name})) (builtins.attrNames checks);
        inherit checks;
      }
    '

assert_json_checks_ok upstream-emulation-pppoe-runtime-render "${result_json}"

echo "PASS upstream-emulation-pppoe-runtime-render"
