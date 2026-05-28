#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${repo_root}/tests/lib/test-common.sh"

result_json="$(mktemp)"
eval_stderr="$(mktemp)"
trap 'rm -f "${result_json}" "${eval_stderr}"' EXIT

nix_eval_json_or_fail \
  dns-service-forward-egress-exception-order \
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
        pkgs = import flake.inputs.nixpkgs { system = builtins.currentSystem; };
        forwardingIntent = {
          normalizedExplicitForwardPairs = [
            {
              "in" = [ "upstream" ];
              "out" = [ "eth0" ];
              action = "accept";
              trafficType = "dns";
              sourcePrefixes = [
                {
                  family = 4;
                  prefix = "10.90.10.1";
                }
              ];
              comment = "allow-dns-service-egress";
            }
          ];
        };
        renderedModel = {
          runtimeTarget.services.dns = {
            listen = [ "10.89.0.2" ];
            allowFrom = [ "10.80.0.0/24" ];
            forwarders = [ ];
            deniedResolverCidrs = [ "1.1.1.1/32" ];
            killSwitch.blockPublicResolvers = true;
            blockDirectEgress = true;
          };
          interfaces = {
            upstream = {
              sourceKind = "p2p";
              renderedIfName = "upstream";
            };
            wan = {
              sourceKind = "wan";
              renderedIfName = "eth0";
            };
          };
        };
        dnsServices = import (repoRoot + "/s88/ControlModule/render/containers/dns-services.nix") {
          inherit lib pkgs renderedModel forwardingIntent;
        };
        nftScript = dnsServices.systemd.services.nft-allow-dns-service.script;
        explicitRules = import (repoRoot + "/s88/ControlModule/firewall/policy/explicit-forwarding.nix") {
          inherit lib forwardingIntent;
          escapeComment = value: value;
          renderTrafficType = name:
            if name == "dns" then [ "meta l4proto udp udp dport { 53 }" "meta l4proto tcp tcp dport { 53 }" ] else [ "" ];
        };
        explicitRulesText = builtins.concatStringsSep "\n" explicitRules;
        has = lib.hasInfix;
        checks = {
          forward_exception_inserted_before_leak_drop =
            has "insert rule inet router forward iifname \"upstream\" oifname \"eth0\" ip saddr 10.90.10.1 udp dport 53 accept comment \"allow-dns-service-forward-egress\"" nftScript
            && has "insert rule inet router forward iifname \"upstream\" ip daddr 1.1.1.1/32 udp dport 53 drop comment \"deny-public-dns-forward-leak\"" nftScript;
          forward_exception_comment_does_not_mask_output_guard =
            !(has "comment \"allow-dns-service-egress\"" nftScript);
          explicit_forwarding_preserves_source_and_dns_match =
            has "iifname \"upstream\" oifname \"eth0\" ip saddr 10.90.10.1 meta l4proto udp udp dport { 53 } accept comment \"allow-dns-service-egress\"" explicitRulesText
            && !(has "iifname \"upstream\" oifname \"eth0\" ip saddr 10.90.10.1 accept comment \"allow-dns-service-egress\"" explicitRulesText);
        };
      in
      {
        ok = builtins.all (name: checks.${name}) (builtins.attrNames checks);
        failed = builtins.filter (name: !(checks.${name})) (builtins.attrNames checks);
        inherit checks;
      }
    '

assert_json_checks_ok dns-service-forward-egress-exception-order "${result_json}"

echo "PASS dns-service-forward-egress-exception-order"
