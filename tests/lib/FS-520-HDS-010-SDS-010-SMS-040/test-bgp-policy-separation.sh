#!/usr/bin/env bash
# GAMP-ID: FS-520-HDS-010-SDS-010-SMS-040
# GAMP-SCOPE: renderer-construction
set -euo pipefail

repo_root="${SMS_TEST_REPO_ROOT:-$(git -C "$(dirname "${BASH_SOURCE[0]}")" rev-parse --show-toplevel)}"
source "${repo_root}/tests/lib/test-common.sh"

result_json="$(mktemp)"
stderr_file="$(mktemp)"
trap 'rm -f "${result_json}" "${stderr_file}"' EXIT

nix_eval_json_or_fail \
  bgp-policy-separation \
  "${result_json}" \
  "${stderr_file}" \
  env REPO_ROOT="${repo_root}" \
    nix eval \
    --extra-experimental-features 'nix-command flakes' \
    --impure --json --expr '
      let
        repoRoot = "path:" + builtins.getEnv "REPO_ROOT";
        flake = builtins.getFlake repoRoot;
        helper = import (flake.outPath + "/s88/ControlModule/render/containers/bgp-services.nix");
        evaluated = helper {
          lib = flake.inputs.nixpkgs.lib;
          renderedModel = {
            loopback.addr4 = "10.255.0.1/32";
            runtimeTarget = {
              routingMode = "bgp";
              bgp = {
                asn = 65010;
                neighbors = [
                  {
                    peer_addr4 = "192.0.2.2/31";
                    peer_asn = 65020;
                  }
                ];
              };
              services.dns.listen = [ "10.53.0.1" ];
              firewall.forwarding = true;
              managementAccess = { allowed = true; };
              publicEgress = { allowed = true; };
            };
            interfaces = {
              tenant-a = {
                sourceKind = "tenant";
                addr4 = "10.10.10.1/24";
                routes = {
                  ipv4 = [{ proto = "connected"; dst = "10.10.10.0/24"; }];
                };
              };
              wan-a = {
                sourceKind = "wan";
                addr4 = "192.0.2.1/31";
              };
            };
          };
        };
        topKeys = builtins.attrNames evaluated;
        serviceKeys = builtins.attrNames (evaluated.services or { });
        frrConfig = evaluated.services.frr.config or "";
        checks = {
          only_services_top_level = topKeys == [ "services" ];
          only_frr_service = serviceKeys == [ "frr" ];
          bgpd_enabled = evaluated.services.frr.bgpd.enable or false;
          no_networking_output = !(evaluated ? networking);
          no_systemd_output = !(evaluated ? systemd);
          no_dns_output = builtins.match ".*10\\.53\\.0\\.1.*" frrConfig == null;
          no_management_policy_output = builtins.match ".*management.*" frrConfig == null;
          no_public_egress_policy_output = builtins.match ".*publicEgress.*" frrConfig == null;
        };
      in
      {
        ok = builtins.all (name: checks.${name}) (builtins.attrNames checks);
        failed = builtins.filter (name: !(checks.${name})) (builtins.attrNames checks);
        inherit checks;
      }
    '

assert_json_checks_ok bgp-policy-separation "${result_json}"

pass "bgp-policy-separation"
