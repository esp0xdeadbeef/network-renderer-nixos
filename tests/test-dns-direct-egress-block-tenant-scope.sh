#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${repo_root}/tests/lib/test-common.sh"

result_json="$(mktemp)"
eval_stderr="$(mktemp)"
trap 'rm -f "${result_json}" "${eval_stderr}"' EXIT

nix_eval_json_or_fail \
  dns-direct-egress-block-tenant-scope \
  "${result_json}" \
  "${eval_stderr}" \
  env REPO_ROOT="${repo_root}" \
    nix eval \
    --extra-experimental-features 'nix-command flakes' \
    --impure --json --expr '
      let
        flake = builtins.getFlake ("path:" + builtins.getEnv "REPO_ROOT");
        lib = flake.inputs.nixpkgs.lib;
        system = "x86_64-linux";
        lab = flake.inputs.network-labs + "/labs/lab-s-sigma/s-router-test-three-site";
        inventoryPath = builtins.toFile "s-router-nixos-inventory.nix" (
          "import " + toString lab + "/getResolvedInventory.nix { renderer = \"nixos\"; }"
        );
        builtHost = flake.lib.renderer.buildHostFromPaths {
          intentPath = lab + "/intent.nix";
          inherit inventoryPath;
          selector = "s-router-test";
          file = "nixos/virtual-machine/nixos-shell-vm/s-router-test/default.nix";
          containerDefaults = {
            autoStart = true;
            additionalCapabilities = [
              "CAP_NET_ADMIN"
              "CAP_NET_RAW"
            ];
          };
          disabled = { };
        };
        cfg = (flake.inputs.nixpkgs.lib.nixosSystem {
          inherit system;
          modules = [ builtHost.renderedHost.containers.nixos-router-core-nebula.config ];
        }).config;
        script = cfg.systemd.services.nft-allow-dns-service.script;
        has = lib.hasInfix;
        checks = {
          no_p2p_upstream_direct_dns_drop =
            !(has "iifname \"upstream\" udp dport 53 drop comment \"deny-direct-dns-egress\"" script)
            && !(has "iifname \"upstream\" tcp dport 53 drop comment \"deny-direct-dns-egress\"" script);
          still_blocks_public_resolver_forward_leaks =
            has "iifname \"upstream\" ip daddr 1.1.1.1/32 udp dport 53 drop comment \"deny-public-dns-forward-leak\"" script
            && has "iifname \"upstream\" ip6 daddr 2606:4700:4700::1111/128 udp dport 53 drop comment \"deny-public-dns-forward-leak\"" script;
        };
      in
      {
        ok = builtins.all (name: checks.${name}) (builtins.attrNames checks);
        failed = builtins.filter (name: !(checks.${name})) (builtins.attrNames checks);
        inherit checks;
      }
    '

assert_json_checks_ok dns-direct-egress-block-tenant-scope "${result_json}"

echo "PASS dns-direct-egress-block-tenant-scope"
