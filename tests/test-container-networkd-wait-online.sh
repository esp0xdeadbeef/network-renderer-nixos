#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

REPO_ROOT="${repo_root}" nix eval \
  --extra-experimental-features 'nix-command flakes' \
  --impure \
  --expr '
    let
      repoRoot = builtins.getEnv "REPO_ROOT";
      flake = builtins.getFlake ("path:" + repoRoot);
      lib = flake.inputs.nixpkgs.lib;
      pkgs = import flake.inputs.nixpkgs { system = builtins.currentSystem; };
      renderedModel = {
        roleName = "policy";
        unitName = "test-router";
        interfaces.transit = {
          sourceKind = "p2p";
          containerInterfaceName = "transit";
          addresses = [ "10.99.0.2/31" "fd00:99::2/127" ];
        };
      };
      renderedModelWithPrimaryBridge =
        renderedModel
        // {
          hostBridge = "br-test";
        };
      module =
        import (repoRoot + "/s88/ControlModule/render/containers/module.nix") {
          inherit
            lib
            renderedModel
            ;
          containerName = "test-router";
          firewallArg = {
            enable = false;
            ruleset = "";
          };
          alarmModel = { };
          uplinks = { };
          wanUplinkName = null;
        };
      moduleWithPrimaryBridge =
        import (repoRoot + "/s88/ControlModule/render/containers/module.nix") {
          inherit lib;
          renderedModel = renderedModelWithPrimaryBridge;
          containerName = "test-router";
          firewallArg = {
            enable = false;
            ruleset = "";
          };
          alarmModel = { };
          uplinks = { };
          wanUplinkName = null;
        };
      evaluated =
        (flake.inputs.nixpkgs.lib.nixosSystem {
          system = builtins.currentSystem;
          modules = [ module ];
        }).config;
      evaluatedWithPrimaryBridge =
        (flake.inputs.nixpkgs.lib.nixosSystem {
          system = builtins.currentSystem;
          modules = [ moduleWithPrimaryBridge ];
        }).config;
    in
    (evaluated.systemd.services.systemd-networkd-wait-online.enable or true) == false
    && (evaluatedWithPrimaryBridge.systemd.services.systemd-networkd-wait-online.enable or true) == true
  ' >/dev/null || {
    echo "FAIL container-networkd-wait-online" >&2
    exit 1
  }

echo "PASS container-networkd-wait-online"
