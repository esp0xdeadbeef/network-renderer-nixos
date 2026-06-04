#!/usr/bin/env bash
# GAMP-ID: FS-800-HDS-010-SDS-010-SMS-010
# GAMP-SCOPE: software-integration-test
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${repo_root}/tests/lib/test-common.sh"

result_json="$(mktemp)"
eval_stderr="$(mktemp)"
trap 'rm -f "${result_json}" "${eval_stderr}"' EXIT

nix_eval_json_or_fail \
  cpm-side-channel-pppoe-dry-render \
  "${result_json}" \
  "${eval_stderr}" \
  env REPO_ROOT="${repo_root}" \
    nix eval \
    --extra-experimental-features 'nix-command flakes' \
    --impure --json --expr '
      let
        repoPath = builtins.getEnv "REPO_ROOT";
        sideChannelRow = {
          backend = "nixos";
          mode = "pppoe";
          handoff = {
            bridge = "br-nix-pppoe";
            mtu = 1492;
          };
          pppoe = {
            server = {
              implementation = "accel-ppp";
              node = "sat-nixos-pppoe-ac";
              handoffBridge = "br-nix-pppoe";
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
        sites = import (repoPath + "/s88/ControlModule/render/dry-config-model/sites.nix") {
          controlPlane = {
            control_plane_model.data.esp.nixos = {
              ipv6 = { };
              routing = { };
              transit = { };
              upstreamEmulation.pppoeNixos = sideChannelRow;
              providerAccess.pppoeNixos = sideChannelRow;
            };
          };
        };
        site = sites.esp.nixos;
        checks = {
          keeps_normal_site_fields = site.ipv6 == { } && site.routing == { } && site.transit == { };
          rejects_upstream_emulation_side_channel = !(site ? upstreamEmulation);
          rejects_provider_access_side_channel = !(site ? providerAccess);
        };
      in
      {
        ok = builtins.all (name: checks.${name}) (builtins.attrNames checks);
        failed = builtins.filter (name: !(checks.${name})) (builtins.attrNames checks);
        inherit checks;
      }
    '

assert_json_checks_ok cpm-side-channel-pppoe-dry-render "${result_json}"

echo "PASS cpm-side-channel-pppoe-dry-render"
