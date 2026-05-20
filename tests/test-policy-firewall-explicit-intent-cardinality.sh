#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${repo_root}/tests/lib/test-common.sh"

nix_eval_true_or_fail \
  policy-firewall-explicit-intent-cardinality \
  env REPO_ROOT="${repo_root}" \
    nix eval \
    --extra-experimental-features 'nix-command flakes' \
    --impure --expr '
      let
        repoRoot = builtins.getEnv "REPO_ROOT";
        flake = builtins.getFlake ("path:" + repoRoot);
        lib = flake.inputs.nixpkgs.lib;
        policy = import (repoRoot + "/s88/ControlModule/firewall/policy/policy.nix") {
          inherit lib;
          communicationContract = {
            trafficTypes = [
              {
                name = "dns";
                match = [
                  { family = "any"; proto = "udp"; dports = [ 53 ]; }
                  { family = "any"; proto = "tcp"; dports = [ 53 ]; }
                ];
              }
            ];
            relations = [
              {
                id = "allow-hetz-dns-service-to-wan";
                action = "allow";
                from = { kind = "service"; name = "hetz-dns-dmz"; };
                to = { kind = "external"; name = "wan"; };
                trafficType = "dns";
              }
            ];
          };
          endpointMap.resolveRelationEndpoint = relation: endpoint:
            if endpoint.kind or null == "service" then [ "downstream-dmz" ]
            else if endpoint.kind or null == "external" then [ "up-client-wan" "up-dmz-wan" ]
            else [ ];
          forwardingIntent.normalizedExplicitForwardPairs = [
            {
              "in" = [ "downstream-dmz" ];
              "out" = [ "up-dmz-wan" ];
              action = "accept";
              trafficType = "dns";
              comment = "allow-hetz-dns-service-to-wan";
            }
          ];
        };
        rules = builtins.concatStringsSep "\n" policy.forwardRules;
      in
        lib.hasInfix "iifname \"downstream-dmz\" oifname \"up-dmz-wan\" meta l4proto udp udp dport { 53 } accept comment \"allow-hetz-dns-service-to-wan\"" rules
        && lib.hasInfix "iifname \"downstream-dmz\" oifname \"up-dmz-wan\" meta l4proto tcp tcp dport { 53 } accept comment \"allow-hetz-dns-service-to-wan\"" rules
        && !(lib.hasInfix "iifname \"downstream-dmz\" oifname \"up-client-wan\"" rules)
    '

echo "PASS policy-firewall-explicit-intent-cardinality"
