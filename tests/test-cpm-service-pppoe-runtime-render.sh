#!/usr/bin/env bash
# GAMP-ID: FS-800-HDS-010-SDS-020-SMS-010
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
          username = "hat-pppoe";
          password = "hat-pppoe";
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
        assembly = import (repoPath + "/s88/ControlModule/mapping/container-runtime/model/container-assembly.nix") {
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
              services.pppoe = clientService;
              effectiveRuntimeRealization.interfaces.provider-handoff.containerInterfaceName = "ens20";
            };
            roleForUnit = _: "core";
            roleConfigForUnit = _: { };
            containerConfigForUnit = _: { };
          };
        };
        runtime = assembly.mkContainerRuntime "nixos-core-testnet-host-isp";
        clientServices = clientEval.config.systemd.services;
        clientPeers = clientEval.config.services.pppd.peers;
        clientPreStart = clientServices."pppd-s88-pppoe-client-provider-handoff".preStart;
        clientServiceUnit = clientServices."pppd-s88-pppoe-client-provider-handoff";
        clientPeerConfig = clientPeers."s88-pppoe-client-provider-handoff".config;
        serverServices = serverEval.config.systemd.services;
        serverScript = serverServices.s88-pppoe-server.script;
        serverUnit = serverServices.s88-pppoe-server;
        checks = {
          client_pppd_enabled = clientEval.config.services.pppd.enable == true;
          client_peer_emitted = clientPeers ? "s88-pppoe-client-provider-handoff";
          client_service_emitted = clientServices ? "pppd-s88-pppoe-client-provider-handoff";
          client_service_wanted_by_multi_user =
            builtins.elem "multi-user.target" (clientServiceUnit.wantedBy or [ ]);
          client_service_restarts =
            (clientServiceUnit.serviceConfig.Restart or null) == "always";
          client_uses_pppoe_plugin = builtins.match ".*plugin pppoe[.]so.*nic-ens20.*" clientPreStart != null;
          client_uses_modeled_credentials = builtins.match ".*hat-pppoe.*" clientPreStart != null;
          client_peer_uses_options_file = builtins.match ".*file /run/pppd/s88-pppoe-client-provider-handoff[.]options.*" clientPeerConfig != null;
          runtime_binds_ppp_device =
            (runtime.bindMounts."/dev/ppp".hostPath or null) == "/dev/ppp"
            && runtime.bindMounts."/dev/ppp".isReadOnly == false;
          runtime_allows_ppp_device =
            builtins.elem { node = "/dev/ppp"; modifier = "rw"; } runtime.allowedDevices;
          server_service_emitted = serverServices ? s88-pppoe-server;
          server_service_tracks_forked_daemon =
            (serverUnit.serviceConfig.Type or null) == "forking"
            && (serverUnit.serviceConfig.PIDFile or null) == "/run/s88-pppoe-server/pppoe-server.pid"
            && (serverUnit.serviceConfig.RuntimeDirectory or null) == "s88-pppoe-server";
          server_uses_pppoe_server = builtins.match ".*pppoe-server.*-I ens20.*" serverScript != null;
          server_uses_pidfile = builtins.match ".*-X '/run/s88-pppoe-server/pppoe-server[.]pid'.*" serverScript != null;
          server_uses_session_addresses =
            builtins.match ".*203[.]0[.]113[.]5.*203[.]0[.]113[.]4.*" serverScript != null;
          server_exposes_tools = serverEval.config.environment.etc ? "s88/pppoe-tools";
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
  '{"unitName":"bad-client","interfaces":{"provider-handoff":{"containerInterfaceName":"ens20"}},"services":{"pppoe":{"client":{"interface":"missing-handoff","runtimeInterface":"ppp0","credentials":{"labOnly":true,"username":"hat-pppoe","password":"hat-pppoe"},"defaultRoute":true}}}}' \
  "services.pppoe.client.interface to name a rendered interface"

run_negative_eval \
  cpm-service-pppoe-missing-server-interface \
  '{"unitName":"bad-server","interfaces":{"provider-handoff":{"containerInterfaceName":"ens20"}},"services":{"pppoe":{"server":{"interface":"missing-handoff","providerAddress":"203.0.113.5","customerAddress":"203.0.113.4","credentials":{"labOnly":true,"username":"hat-pppoe","password":"hat-pppoe"},"implementation":"rp-pppoe"}}}}' \
  "services.pppoe.server.interface to name a rendered interface"

run_negative_eval \
  cpm-service-pppoe-unsupported-implementation \
  '{"unitName":"bad-server","interfaces":{"provider-handoff":{"containerInterfaceName":"ens20"}},"services":{"pppoe":{"server":{"interface":"provider-handoff","providerAddress":"203.0.113.5","customerAddress":"203.0.113.4","credentials":{"labOnly":true,"username":"hat-pppoe","password":"hat-pppoe"},"implementation":"accel-ppp"}}}}' \
  "supported implementation"

echo "PASS cpm-service-pppoe-runtime-render"
