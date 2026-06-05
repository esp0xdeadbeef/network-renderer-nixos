#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${repo_root}/tests/lib/test-common.sh"

result_json="$(mktemp)"
eval_stderr="$(mktemp)"
trap 'rm -f "${result_json}" "${eval_stderr}"' EXIT

nix_eval_json_or_fail \
  dns-public-resolver-block-cpm-contract \
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

        render = dns:
          import (repoRoot + "/s88/ControlModule/render/containers/dns-services.nix") {
            inherit lib pkgs;
            renderedModel = {
              runtimeTarget.services.dns = dns;
              interfaces = {
                access = {
                  sourceKind = "tenant";
                  renderedIfName = "access0";
                };
                wan = {
                  sourceKind = "wan";
                  renderedIfName = "eth0";
                };
              };
            };
          };

        noBlock = render {
          listen = [ "10.20.0.1" ];
          allowFrom = [ "10.20.0.0/24" ];
          forwarders = [ ];
          deniedResolverCidrs = [ ];
          killSwitch.blockPublicResolvers = false;
          blockDirectEgress = false;
        };

        explicitBlock = render {
          listen = [ "10.20.0.1" "fd00:20::1" ];
          allowFrom = [ "10.20.0.0/24" "fd00:20::/64" ];
          forwarders = [ ];
          deniedResolverCidrs = [
            "1.1.1.1/32"
            "2606:4700:4700::1111/128"
          ];
          killSwitch.blockPublicResolvers = true;
          blockDirectEgress = false;
        };

        noBlockScript = noBlock.systemd.services.nft-allow-dns-service.script;
        explicitBlockScript = explicitBlock.systemd.services.nft-allow-dns-service.script;
        has = lib.hasInfix;
        checks = {
          no_block_does_not_invent_public_resolver_drops =
            !(has "deny-public-dns-forward-leak" noBlockScript)
            && !(has "deny-public-dns-output-leak" noBlockScript)
            && !(has "ip daddr 1.1.1.1/32" noBlockScript)
            && !(has "ip6 daddr 2606:4700:4700::1111/128" noBlockScript);

          explicit_block_renders_forward_public_resolver_drops =
            has "insert rule inet router forward iifname \"access0\" ip daddr 1.1.1.1/32 udp dport 53 drop comment \"deny-public-dns-forward-leak\"" explicitBlockScript
            && has "insert rule inet router forward iifname \"access0\" ip daddr 1.1.1.1/32 tcp dport 53 drop comment \"deny-public-dns-forward-leak\"" explicitBlockScript
            && has "insert rule inet router forward iifname \"access0\" ip6 daddr 2606:4700:4700::1111/128 udp dport 53 drop comment \"deny-public-dns-forward-leak\"" explicitBlockScript
            && has "insert rule inet router forward iifname \"access0\" ip6 daddr 2606:4700:4700::1111/128 tcp dport 53 drop comment \"deny-public-dns-forward-leak\"" explicitBlockScript;

          explicit_block_renders_output_public_resolver_drops =
            has "add rule inet router output ip daddr 1.1.1.1/32 udp dport 53 drop comment \"deny-public-dns-output-leak\"" explicitBlockScript
            && has "add rule inet router output ip daddr 1.1.1.1/32 tcp dport 53 drop comment \"deny-public-dns-output-leak\"" explicitBlockScript
            && has "add rule inet router output ip6 daddr 2606:4700:4700::1111/128 udp dport 53 drop comment \"deny-public-dns-output-leak\"" explicitBlockScript
            && has "add rule inet router output ip6 daddr 2606:4700:4700::1111/128 tcp dport 53 drop comment \"deny-public-dns-output-leak\"" explicitBlockScript;

          explicit_block_keeps_wan_out_of_forward_leak_drops =
            !(has "iifname \"eth0\" ip daddr 1.1.1.1/32" explicitBlockScript)
            && !(has "iifname \"eth0\" ip6 daddr 2606:4700:4700::1111/128" explicitBlockScript);
        };
      in
      {
        ok = builtins.all (name: checks.${name}) (builtins.attrNames checks);
        failed = builtins.filter (name: !(checks.${name})) (builtins.attrNames checks);
        inherit checks;
      }
    '

assert_json_checks_ok dns-public-resolver-block-cpm-contract "${result_json}"

echo "PASS dns-public-resolver-block-cpm-contract"
