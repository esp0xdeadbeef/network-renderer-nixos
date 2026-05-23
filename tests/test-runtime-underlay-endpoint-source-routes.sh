#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

source "${repo_root}/tests/lib/test-common.sh"

example_root="$(flake_input_path network-labs)/examples/s-router-overlay-dns-lane-policy"
intent_path="${example_root}/intent.nix"
inventory_path="${example_root}/inventory-nixos.nix"

nix_eval_true_or_fail "runtime-underlay-endpoint-source-routes" env REPO_ROOT="${repo_root}" \
INTENT_PATH="${intent_path}" \
INVENTORY_PATH="${inventory_path}" \
  nix eval \
    --extra-experimental-features 'nix-command flakes' \
    --impure --expr '
      let
        flake = builtins.getFlake ("path:" + builtins.getEnv "REPO_ROOT");
        builtContainers = flake.lib.containers.buildForBox {
          boxName = "s-router-test";
          system = "x86_64-linux";
          intentPath = builtins.getEnv "INTENT_PATH";
          inventoryPath = builtins.getEnv "INVENTORY_PATH";
        };
        cfg =
          (flake.inputs.nixpkgs.lib.nixosSystem {
            system = "x86_64-linux";
            modules = [ builtContainers."b-router-upstream-selector".config ];
          }).config;
        bindMounts = builtContainers."b-router-upstream-selector".bindMounts or { };
        ruleset = cfg.networking.nftables.ruleset;
        serviceNames = builtins.attrNames cfg.systemd.services;
        dynamicRouteServices =
          builtins.filter
            (name: builtins.match "s88-delegated-prefix-route-core-isp-.*" name != null)
            serviceNames;
        scripts = map (name: builtins.readFile cfg.systemd.services.${name}.serviceConfig.ExecStart) dynamicRouteServices;
        hasIpv4EndpointRoute =
          builtins.any
            (script:
              builtins.match ".*?/run/secrets/site-c-lighthouse-public-ipv4.*" script != null
              && builtins.match ".*?family=4.*" script != null
              && builtins.match ".*?ip route replace.*?\\$prefix.*" script != null)
            scripts;
        hasIpv6EndpointRoute =
          builtins.any
            (script:
              builtins.match ".*?/run/secrets/site-c-lighthouse-public-ipv6.*" script != null
              && builtins.match ".*?family=6.*" script != null
              && builtins.match ".*?ip -6 route replace.*?\\$prefix.*" script != null)
            scripts;
        hasIpv4SecretMount =
          bindMounts."/run/secrets/site-c-lighthouse-public-ipv4".hostPath or null
            == "/run/secrets/site-c-lighthouse-public-ipv4";
        hasIpv6SecretMount =
          bindMounts."/run/secrets/site-c-lighthouse-public-ipv6".hostPath or null
            == "/run/secrets/site-c-lighthouse-public-ipv6";
        hasUdpUnderlayFirewall =
          flake.inputs.nixpkgs.lib.hasInfix
            "iifname \"core-nebula\" oifname \"core-isp\" meta l4proto udp udp dport { 4242 } accept"
            ruleset;
        hasTcpUnderlayFirewall =
          flake.inputs.nixpkgs.lib.hasInfix
            "iifname \"core-nebula\" oifname \"core-isp\" meta l4proto tcp tcp dport { 4242 } accept"
            ruleset;
      in
        hasIpv4EndpointRoute && hasIpv6EndpointRoute
        && hasIpv4SecretMount && hasIpv6SecretMount
        && hasUdpUnderlayFirewall && hasTcpUnderlayFirewall
    '

pass "runtime-underlay-endpoint-source-routes"
