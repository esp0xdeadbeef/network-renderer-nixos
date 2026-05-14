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
      pkgs = flake.inputs.nixpkgs.legacyPackages.x86_64-linux;
      runtimeTarget = {
        forwardingIntent = {
          mode = "explicit-selector-forwarding";
          rules = [
            {
              action = "accept";
              fromInterface = "core-nebula";
              toInterface = "core";
              sourceFiles = [ "/run/secrets/access-node-ipv6-prefix-hostile" ];
              family = 6;
              relationId = "runtime-routed-prefix-public-egress";
            }
          ];
        };
      };
      forwardingIntent =
        import (repoRoot + "/s88/ControlModule/firewall/lookup/forwarding-intent.nix") {
          inherit lib runtimeTarget;
          interfaces = {
            core-nebula.containerInterfaceName = "core-nebula";
            core.containerInterfaceName = "core";
          };
        };
      firewallRules =
        import (repoRoot + "/s88/ControlModule/firewall/policy/explicit-forwarding.nix") {
          inherit lib forwardingIntent;
          escapeComment = value: value;
          renderTrafficType = _: [ "" ];
        };
      render =
        import (repoRoot + "/s88/ControlModule/render/container-networks.nix") {
          inherit lib forwardingIntent;
          uplinks = { };
          wanUplinkName = null;
          containerModel = {
            interfaces = {
              core-nebula = {
                containerInterfaceName = "core-nebula";
                addresses = [ "fd42:dead:cafe:1000::b/127" ];
              };
              core = {
                containerInterfaceName = "core";
                addresses = [ "fd42:dead:cafe:1000::5/127" ];
              };
            };
          };
        };
      dynamicForwarding =
        import (repoRoot + "/s88/ControlModule/render/containers/module/dynamic-forwarding.nix") {
          inherit lib pkgs;
          dynamicSourceForwardRules = render.dynamicSourceForwardRules;
        };
      service = dynamicForwarding.config.systemd.services."s88-dynamic-forward-0" or null;
    in
      firewallRules == [ ]
      && render.dynamicSourceForwardRules == [
        {
          action = "accept";
          comment = "runtime-routed-prefix-public-egress";
          family = 6;
          inIf = "core-nebula";
          outIf = "core";
          sourceFile = "/run/secrets/access-node-ipv6-prefix-hostile";
        }
      ]
      && service != null
      && builtins.match ".*ip6 saddr.*" service.script != null
  ' >/dev/null

echo "PASS dynamic-source-forwarding"
