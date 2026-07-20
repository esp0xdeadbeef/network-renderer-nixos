#!/usr/bin/env bash
# GAMP-ID: FS-540-HDS-010-SDS-010-SMS-045
# GAMP-SCOPE: software-module-test
set -euo pipefail

repo_root="${SMS_TEST_REPO_ROOT:-$(git -C "$(dirname "${BASH_SOURCE[0]}")" rev-parse --show-toplevel)}"
source "${repo_root}/tests/lib/test-common.sh"

nix_eval_true_or_fail "FS-540 SMS-045 dual-stack local DNS return path" \
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
            services.dns = {
              outgoingInterfaces = [
                "10.54.46.1"
                "fd42:540:46::1"
              ];
              roles.recursion.outgoingInterfaces = [
                "10.54.46.1"
                "fd42:540:46::1"
              ];
            };
            interfaces.lan0 = {
              addr4 = "10.54.46.1/24";
              addr6 = "fd42:0540:0046:0000:0000:0000:0000:0001/64";
            };
            routeHelpers.addressNetworkPrefix = cidr:
              if cidr == "10.54.46.1/24" then "10.54.46.0/24"
              else if cidr == "fd42:0540:0046:0000:0000:0000:0000:0001/64" then "fd42:0540:0046::/64"
              else null;
          };
          routes = localOriginDns.routesByInterface 1002 [ "lan0" ];
          rules = localOriginDns.rules 1002 1002 [ "lan0" ];
          lanRoutes = routes.lan0 or [ ];
          hasRule = family: source:
            builtins.any
              (rule:
                (rule.Family or null) == family
                && (rule.From or null) == source
                && (rule.Priority or null) == 1002
                && (rule.Table or null) == 1002
                && !(rule ? IncomingInterface))
              rules;
          hasRoute = destination:
            builtins.any
              (route:
                (route.Destination or null) == destination
                && (route.Table or null) == 1002
                && (route._s88IntentKind or null) == "service-dns-local-origin-return")
              lanRoutes;
          require = condition: message: if condition then true else throw message;
        in
          require (hasRule "ipv4" "10.54.46.1/32")
            "local DNS IPv4 replies must select the modeled return table without incoming-interface context"
          && require (hasRule "ipv6" "fd42:540:46::1/128")
            "equivalent compressed and expanded IPv6 forms must produce a local DNS return rule"
          && require (hasRoute "10.54.46.0/24")
            "local DNS IPv4 return subnet must remain in the selected table"
          && require (hasRoute "fd42:0540:0046::/64")
            "local DNS IPv6 return subnet must remain in the selected table"
      '

echo "PASS FS-540-HDS-010-SDS-010-SMS-045 dual-stack local DNS return path"
