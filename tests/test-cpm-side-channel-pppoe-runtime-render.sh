#!/usr/bin/env bash
# GAMP-ID: FS-800-HDS-010-SDS-020-SMS-010
# GAMP-SCOPE: software-module-test
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${repo_root}/tests/lib/test-common.sh"

result_json="$(mktemp)"
eval_stderr="$(mktemp)"
trap 'rm -f "${result_json}" "${eval_stderr}"' EXIT

nix_eval_json_or_fail \
  cpm-side-channel-pppoe-runtime-render \
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
        sideChannelRow = {
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
        evalForSite =
          site:
          let
            clientModule = import (repoPath + "/s88/ControlModule/render/containers/module/pppoe.nix") {
              inherit lib pkgs;
              renderedModel = {
                unitName = "nixos-router-core-isp-a";
                interfaces.pppoe-wan.containerInterfaceName = "wan-pppoe";
                inherit site;
              };
            };
            clientEval = lib.nixosSystem {
              inherit system;
              modules = [ clientModule.config ];
            };
            clientRuntime = import (repoPath + "/s88/ControlModule/render/containers/emission.nix") {
              inherit lib;
              debugEnabled = false;
              deploymentHostName = "s-router-nixos";
              containerName = "nixos-router-core-isp-a";
              renderedModel = {
                unitName = "nixos-router-core-isp-a";
                interfaces.pppoe-wan.containerInterfaceName = "wan-pppoe";
                inherit site;
              };
              firewallArg = { enable = false; };
              alarmModel = { };
              uplinks = { };
              wanUplinkName = null;
            };
          in
          {
            inherit clientEval clientRuntime;
          };
        upstreamEval = evalForSite { upstreamEmulation.pppoeNixos = sideChannelRow; };
        providerEval = evalForSite { providerAccess.pppoeNixos = sideChannelRow; };
        upstreamServerContainers = import (repoPath + "/s88/ControlModule/render/pppoe-server-containers.nix") {
          inherit lib;
          cpm = {
            control_plane_model.data.esp.nixos.upstreamEmulation.pppoeNixos = sideChannelRow;
          };
          hostName = "s-router-nixos";
          hostPlan.selectedUnits = [ "esp::nixos::esp-nixos-router-core-isp-a" ];
        };
        providerServerContainers = import (repoPath + "/s88/ControlModule/render/pppoe-server-containers.nix") {
          inherit lib;
          cpm = {
            control_plane_model.data.esp.nixos.providerAccess.pppoeNixos = sideChannelRow;
          };
          hostName = "s-router-nixos";
          hostPlan.selectedUnits = [ "esp::nixos::esp-nixos-router-core-isp-a" ];
        };
        noPppdPeer =
          eval:
          !(eval.clientEval.config.services.pppd.peers ? "s88-pppoe-client-pppoe-wan");
        noPppDevice =
          eval:
          !(eval.clientRuntime.bindMounts ? "/dev/ppp")
          && !(builtins.elem { node = "/dev/ppp"; modifier = "rw"; } eval.clientRuntime.allowedDevices);
        checks = {
          ignores_legacy_client_peer = noPppdPeer upstreamEval;
          ignores_legacy_client_runtime = noPppDevice upstreamEval;
          ignores_legacy_server_container = upstreamServerContainers == { };
          rejects_provider_client_peer = noPppdPeer providerEval;
          rejects_provider_client_runtime = noPppDevice providerEval;
          rejects_provider_server_container = providerServerContainers == { };
        };
      in
      {
        ok = builtins.all (name: checks.${name}) (builtins.attrNames checks);
        failed = builtins.filter (name: !(checks.${name})) (builtins.attrNames checks);
        inherit checks;
      }
    '

assert_json_checks_ok cpm-side-channel-pppoe-runtime-render "${result_json}"

echo "PASS cpm-side-channel-pppoe-runtime-render"
