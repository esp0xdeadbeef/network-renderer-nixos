#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${repo_root}/tests/lib/test-common.sh"

example_root="${repo_root}/tests/fixtures/s-router-overlay-dns-lane-policy"

nix_eval_true_or_fail "host-build-artifact-module" env REPO_ROOT="${repo_root}" \
INTENT_PATH="${example_root}/intent.nix" \
INVENTORY_PATH="${example_root}/inventory-nixos.nix" \
  nix eval \
    --extra-experimental-features 'nix-command flakes' \
    --impure --expr '
      let
        flake = builtins.getFlake ("path:" + builtins.getEnv "REPO_ROOT");
        host = import (builtins.getEnv "REPO_ROOT" + "/tests/nix/build-host-from-paths.nix") {
          selector = "s-router-test";
          system = "x86_64-linux";
          intentPath = builtins.getEnv "INTENT_PATH";
          inventoryPath = builtins.getEnv "INVENTORY_PATH";
        };
        etc = host.artifactModule.environment.etc;
      in
        builtins.hasAttr "network-artifacts/compiler.json" etc
        && builtins.hasAttr "network-artifacts/forwarding.json" etc
        && builtins.hasAttr "network-artifacts/control-plane.json" etc
        && builtins.hasAttr "network-artifacts/intent.json" etc
        && builtins.hasAttr "network-artifacts/inventory.json" etc
        && builtins.hasAttr "network-artifacts/rendered-host.json" etc
        && builtins.hasAttr "network-artifacts/debug-bundle.json" etc
        && builtins.hasAttr "network-renderer/network-renderer-nixos.json" etc
    '

nix_eval_true_or_fail "host-module-api" env REPO_ROOT="${repo_root}" \
EXAMPLE_ROOT="${example_root}" \
INTENT_PATH="${example_root}/intent.nix" \
INVENTORY_PATH="${example_root}/inventory-nixos.nix" \
  nix eval \
    --extra-experimental-features 'nix-command flakes' \
    --impure --expr '
      let
        flake = builtins.getFlake ("path:" + builtins.getEnv "REPO_ROOT");
        lib = flake.inputs.nixpkgs.lib;
        system = "x86_64-linux";
        cpmWithArtifacts = rec {
          control_plane_model = {
            meta.traceId = "test-host-module-artifact-pass-through";
            deployment.hosts.s-router-test-clients = {
              accessHandoff = {
                kind = "pppoe";
                server = "emulated-isp";
              };
              uplinks = { };
            };
            render.hosts.s-router-test-clients.deploymentHost = "s-router-test-clients";
            realization.nodes = { };
            data.active-lab.test-clients = {
              enterprise = "active-lab";
              siteName = "test-clients";
              runtimeTargets = { };
              endpointAssignment = { };
            };
          };
          deploymentHosts = control_plane_model.deployment.hosts;
          realization = control_plane_model.realization;
          render = control_plane_model.render;
          compilerOut = {
            sentinel = "compiler-from-cpm-wrapper";
          };
          forwardingOut = {
            sentinel = "forwarding-from-cpm-wrapper";
            enterprise = {
              sentinel = { };
            };
          };
        };
        module = flake.lib.renderer.hostModule {
          inherit lib system;
          hostName = "s-router-test-clients";
          cpm = cpmWithArtifacts;
          selectorFile = "tests/test-host-build-artifact-module.sh";
        };
        evaluated = lib.nixosSystem {
          inherit system;
          modules = [ module ];
        };
        config = evaluated.config;
        etc = config.environment.etc;
        compilerArtifact = builtins.fromJSON etc."network-artifacts/compiler.json".text;
        forwardingArtifact = builtins.fromJSON etc."network-artifacts/forwarding.json".text;
        containerNames = builtins.attrNames (config.containers or { });
        accessClient = config.containers."s-router-access-client" or { };
      in
        builtins.hasAttr "network-artifacts/compiler.json" etc
        && builtins.hasAttr "network-artifacts/forwarding.json" etc
        && builtins.hasAttr "network-artifacts/rendered-host.json" etc
        && builtins.hasAttr "network-renderer/network-renderer-nixos.json" etc
        && compilerArtifact.sentinel == "compiler-from-cpm-wrapper"
        && forwardingArtifact.sentinel == "forwarding-from-cpm-wrapper"
        && builtins.attrNames (forwardingArtifact.enterprise or { }) != [ ]
        && config.networking.useNetworkd == false
        && config.systemd.network.enable == false
        && builtins.attrNames (config.containers or { }) == [ ]
    '

echo "PASS host-build-artifact-module"
