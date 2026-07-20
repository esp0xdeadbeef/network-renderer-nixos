#!/usr/bin/env bash
# GAMP-ID: FS-380-HDS-020-SDS-010-SMS-120
# GAMP-SCOPE: software-module-test
set -euo pipefail

repo_root="${SMS_TEST_REPO_ROOT:-$(git -C "$(dirname "${BASH_SOURCE[0]}")" rev-parse --show-toplevel)}"
source "${repo_root}/tests/lib/test-common.sh"

nix_eval_true_or_fail "FS-380 SMS-120 recursive DNS local-origin fallback" \
  env REPO_ROOT="${repo_root}" \
    nix eval \
      --extra-experimental-features 'nix-command flakes' \
      --impure --expr '
        let
          repoRoot = builtins.getEnv "REPO_ROOT";
          flake = builtins.getFlake ("path:" + repoRoot);
          lib = flake.inputs.nixpkgs.lib;
          localOriginDns = import (repoRoot + "/s88/ControlModule/render/container-networks/policy-routing/local-origin-dns.nix") {
            inherit lib;
            services = {
              dns = {
                listen = [ "192.168.1.1" ];
                outgoingInterfaces = [ ];
                roles.recursion.outgoingInterfaces = [ ];
              };
            };
            interfaces = {
              lan2 = {
                addr4 = "192.168.1.1/24";
              };
              access-vlan2 = {
                addr4 = "10.10.0.0/31";
              };
            };
            routeHelpers = {
              addressNetworkPrefix = cidr:
                if cidr == "192.168.1.1/24" then "192.168.1.0/24"
                else if cidr == "10.10.0.0/31" then "10.10.0.0/31"
                else null;
            };
          };
          routesByInterface = localOriginDns.routesByInterface 1002 [ "lan2" "access-vlan2" ];
          rules = localOriginDns.rules 1002 1002 [ "lan2" "access-vlan2" ];
          lan2Routes = routesByInterface.lan2 or [ ];
          hasReturnRoute =
            builtins.any
              (route:
                (route.Destination or null) == "192.168.1.0/24"
                && (route.Scope or null) == "link"
                && (route.Table or null) == 1002
                && (route.policyOnly or false) == true
                && (route._s88IntentKind or null) == "service-dns-local-origin-return")
              lan2Routes;
          hasLocalOriginRule =
            builtins.any
              (rule:
                (rule.Family or null) == "ipv4"
                && (rule.From or null) == "192.168.1.1/32"
                && (rule.Priority or null) == 1002
                && (rule.Table or null) == 1002
                && !(builtins.hasAttr "IncomingInterface" rule))
              rules;
          noP2pSourceRule =
            !(builtins.any (rule: (rule.From or null) == "10.10.0.0/32") rules);
          require = cond: msg: if cond then true else throw msg;
        in
          require hasReturnRoute
            "recursive DNS local origin must add a policy-only return route for the listener subnet"
          && require hasLocalOriginRule
            "recursive DNS local origin must select the egress policy table from the listener host address"
          && require noP2pSourceRule
            "recursive DNS fallback must not mistake unrelated p2p addresses for DNS listener sources"
      '

echo "PASS FS-380-HDS-020-SDS-010-SMS-120 recursive DNS local-origin fallback"
