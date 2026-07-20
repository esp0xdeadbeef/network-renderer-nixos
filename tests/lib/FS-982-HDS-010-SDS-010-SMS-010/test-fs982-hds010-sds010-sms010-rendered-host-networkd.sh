#!/usr/bin/env bash
# GAMP-ID: FS-982-HDS-010-SDS-010-SMS-010
# GAMP-SCOPE: software-module-test
set -euo pipefail

repo_root="${SMS_TEST_REPO_ROOT:-$(git -C "$(dirname "${BASH_SOURCE[0]}")" rev-parse --show-toplevel)}"
source "${repo_root}/tests/lib/test-common.sh"

nix_eval_true_or_fail "FS-982 rendered host bridges force networkd" \
  env REPO_ROOT="${repo_root}" \
    nix eval \
      --extra-experimental-features 'nix-command flakes' \
      --impure --expr '
        let
          repoRoot = builtins.getEnv "REPO_ROOT";
          flake = builtins.getFlake ("path:" + repoRoot);
          lib = flake.inputs.nixpkgs.lib;
          system = "x86_64-linux";
          cpm = rec {
            control_plane_model = {
              meta.traceId = "FS-982-HDS-010-SDS-010-SMS-010";
              deployment.hosts.s-router-prod-like = {
                bridgeNetworks = {
                  br-lan-trunk = { };
                  br-wan6 = { };
                };
                uplinks = { };
              };
              render.hosts.s-router-prod-like.deploymentHost = "s-router-prod-like";
              realization.nodes = { };
              data.active-lab.test = {
                enterprise = "active-lab";
                siteName = "test";
                runtimeTargets = { };
                endpointAssignment = { };
              };
            };
            deploymentHosts = control_plane_model.deployment.hosts;
            realization = control_plane_model.realization;
            render = control_plane_model.render;
          };
          module = flake.lib.renderer.hostModule {
            inherit lib system;
            hostName = "s-router-prod-like";
            cpm = cpm;
            selectorFile = "tests/test-fs982-hds010-sds010-sms010-rendered-host-networkd.sh";
          };
          evaluated = lib.nixosSystem {
            inherit system;
            modules = [ module ];
          };
          config = evaluated.config;
          netdevs = config.systemd.network.netdevs or { };
          require = cond: msg: if cond then true else throw msg;
        in
          require (builtins.hasAttr "10-br-lan-trunk" netdevs)
            "renderer must emit the explicit host bridge br-lan-trunk"
          && require (builtins.hasAttr "10-br-wan6" netdevs)
            "renderer must emit the explicit host bridge br-wan6"
          && require (config.networking.useNetworkd == true)
            "rendered host bridges must force networking.useNetworkd=true"
          && require (config.systemd.network.enable == true)
            "rendered host bridges must force systemd.network.enable=true"
          && require (config.networking.useDHCP == false)
            "rendered host bridges must disable legacy global DHCP"
      '

echo "PASS FS-982 rendered host bridges force networkd"
