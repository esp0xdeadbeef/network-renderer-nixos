#!/usr/bin/env bash
# GAMP-ID: FS-310-HDS-010-SDS-010-SMS-130
# GAMP-SCOPE: software-module-test
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${repo_root}/tests/lib/test-common.sh"

result_json="$(mktemp)"
eval_stderr="$(mktemp)"
trap 'rm -f "${result_json}" "${eval_stderr}"' EXIT

nix_eval_json_or_fail \
  access-any-forwarding-route-selectability \
  "${result_json}" \
  "${eval_stderr}" \
  env REPO_ROOT="${repo_root}" \
    nix eval \
    --extra-experimental-features 'nix-command flakes' \
    --impure --json --expr '
      let
        repoRoot = builtins.getEnv "REPO_ROOT";
        flake = builtins.getFlake ("path:" + repoRoot);
        lib = flake.inputs.nixpkgs.lib;
        renderedInterfaceNames = {
          lan = "lan2";
          transit = "access-vlan2";
          dns = "site-dns";
        };
        interfaces = {
          lan.routes = [ ];
          transit.routes = [ ];
          dns.routes = [ ];
        };
        forwardingRules = [
          {
            action = "accept";
            fromInterface = "lan2";
            toInterface = "access-vlan2";
            trafficType = "any";
          }
          {
            action = "accept";
            fromInterface = "lan2";
            toInterface = "site-dns";
            trafficType = "dns";
          }
        ];
        sourceInterfaces = import (repoRoot + "/s88/ControlModule/render/container-networks/policy-routing/source-interfaces.nix") {
          inherit lib interfaces renderedInterfaceNames forwardingRules;
          interfaceNames = [ "lan" "transit" "dns" ];
          addressForFamily = _: _: null;
          ipv4PeerFor31 = _: null;
          ipv6PeerFor127 = _: null;
        };
        forwardingRuleSet = import (repoRoot + "/s88/ControlModule/render/container-networks/policy-routing/forwarding-rules.nix") {
          inherit lib;
          containerModel = {
            runtimeTarget.forwardingIntent.rules = forwardingRules;
          };
        };
      in
      {
        source_for_any_transit = sourceInterfaces.forTarget "access-vlan2";
        rules_for_any_transit = sourceInterfaces.forTargetRules "access-vlan2";
        source_for_dns = sourceInterfaces.forTarget "site-dns";
        any_route_selectable =
          forwardingRuleSet.hasAcceptForwardingRuleForRoute "lan2" "access-vlan2" {
            dst = "0.0.0.0/0";
            via4 = "10.10.0.1";
          };
        dns_without_source_scope_route_selectable =
          forwardingRuleSet.hasAcceptForwardingRuleForRoute "lan2" "site-dns" {
            dst = "10.19.0.10/32";
            via4 = "10.10.0.1";
          };
      }
    '

if ! jq -e '
  (.source_for_any_transit | index("lan") != null)
  and (.rules_for_any_transit | index("lan") != null)
  and (.source_for_dns | index("lan") == null)
  and .any_route_selectable == true
  and .dns_without_source_scope_route_selectable == false
' "${result_json}" >/dev/null; then
  echo "FAIL: trafficType=any access handoff route selectability regressed" >&2
  cat "${result_json}" >&2
  exit 1
fi

echo "PASS access-any-forwarding-route-selectability"
