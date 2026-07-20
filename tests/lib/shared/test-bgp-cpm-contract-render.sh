#!/usr/bin/env bash
# GAMP-ID: FS-480-HDS-010-SDS-010-SMS-010
# GAMP-ID: FS-520-HDS-010-SDS-010-SMS-010
# GAMP-ID: FS-780-HDS-010-SDS-010-SMS-010
# GAMP-SCOPE: renderer-hat-preparation
set -euo pipefail

repo_root="${SMS_TEST_REPO_ROOT:-$(git -C "$(dirname "${BASH_SOURCE[0]}")" rev-parse --show-toplevel)}"
source "${repo_root}/tests/lib/test-common.sh"

result_json="$(mktemp)"
eval_stderr="$(mktemp)"
trap 'rm -f "${result_json}" "${eval_stderr}"' EXIT

nix_eval_json_or_fail \
  bgp-cpm-contract-render \
  "${result_json}" \
  "${eval_stderr}" \
  env REPO_ROOT="${repo_root}" \
    nix eval \
    --extra-experimental-features 'nix-command flakes' \
    --impure --json --expr '
      let
        repoRoot = "path:" + builtins.getEnv "REPO_ROOT";
        flake = builtins.getFlake repoRoot;
        lib = flake.inputs.nixpkgs.lib;
        helper = import (flake.outPath + "/s88/ControlModule/render/containers/bgp-services.nix");
        render = renderedModel: helper { inherit lib renderedModel; };
        edgeA = render {
          loopback = {
            addr4 = "10.255.0.1/32";
            addr6 = "fd42:ffff::1/128";
          };
          runtimeTarget = {
            routingMode = "bgp";
            bgp = {
              asn = 65010;
              neighbors = [
                {
                  peer_addr4 = "192.0.2.2/31";
                  peer_addr6 = "2001:db8:100::2/127";
                  peer_asn = 65020;
                }
              ];
            };
          };
          interfaces = {
            to-edge-b = {
              sourceKind = "wan";
              addr4 = "192.0.2.1/31";
              addr6 = "2001:db8:100::1/127";
            };
            tenant-a = {
              sourceKind = "tenant";
              addr4 = "10.10.10.1/24";
              addr6 = "fd42:10:10::1/64";
              routes = {
                ipv4 = [{ proto = "connected"; dst = "10.10.10.0/24"; }];
                ipv6 = [{ proto = "connected"; dst = "fd42:10:10::/64"; }];
              };
            };
          };
        };
        edgeB = render {
          loopback = {
            addr4 = "10.255.0.2/32";
            addr6 = "fd42:ffff::2/128";
          };
          runtimeTarget = {
            routingMode = "bgp";
            bgp = {
              asn = 65020;
              neighbors = [
                {
                  peer_addr4 = "192.0.2.1/31";
                  peer_addr6 = "2001:db8:100::1/127";
                  peer_asn = 65010;
                }
              ];
            };
          };
          interfaces = {
            to-edge-a = {
              sourceKind = "wan";
              addr4 = "192.0.2.2/31";
              addr6 = "2001:db8:100::2/127";
            };
            tenant-b = {
              sourceKind = "tenant";
              addr4 = "10.20.20.1/24";
              addr6 = "fd42:20:20::1/64";
              routes = {
                ipv4 = [{ proto = "connected"; dst = "10.20.20.0/24"; }];
                ipv6 = [{ proto = "connected"; dst = "fd42:20:20::/64"; }];
              };
            };
          };
        };
        edgeAConfig = edgeA.services.frr.config or "";
        edgeBConfig = edgeB.services.frr.config or "";
        checks = {
          edge_a_enabled = edgeA.services.frr.bgpd.enable or false;
          edge_b_enabled = edgeB.services.frr.bgpd.enable or false;
          edge_a_asn = builtins.match ".*router bgp 65010.*" edgeAConfig != null;
          edge_b_asn = builtins.match ".*router bgp 65020.*" edgeBConfig != null;
          edge_a_ipv4_peer = builtins.match ".*neighbor 192\\.0\\.2\\.2 remote-as 65020.*" edgeAConfig != null;
          edge_b_ipv4_peer = builtins.match ".*neighbor 192\\.0\\.2\\.1 remote-as 65010.*" edgeBConfig != null;
          edge_a_ipv6_peer = builtins.match ".*neighbor 2001:db8:100::2 remote-as 65020.*" edgeAConfig != null;
          edge_b_ipv6_peer = builtins.match ".*neighbor 2001:db8:100::1 remote-as 65010.*" edgeBConfig != null;
          edge_a_tenant_network = builtins.match ".*network 10\\.10\\.10\\.0/24.*" edgeAConfig != null;
          edge_b_tenant_network = builtins.match ".*network 10\\.20\\.20\\.0/24.*" edgeBConfig != null;
          no_route_reflector_default = builtins.match ".*route-reflector-client.*" (edgeAConfig + edgeBConfig) == null;
        };
      in
      {
        ok = builtins.all (name: checks.${name}) (builtins.attrNames checks);
        failed = builtins.filter (name: !(checks.${name})) (builtins.attrNames checks);
        inherit checks;
      }
    '

assert_json_checks_ok bgp-cpm-contract-render "${result_json}"

echo "PASS bgp-cpm-contract-render"
