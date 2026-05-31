#!/usr/bin/env bash
# GAMP-ID: USR-MODEL-001-FS-001-HDS-001-SDS-001-003-SMS-001-007
# GAMP-ID: USR-MODEL-001-FS-001-HDS-001-SDS-001-003-SMS-001-CMC-001-007
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
      render =
        import (repoRoot + "/s88/ControlModule/render/container-networks.nix") {
          inherit lib;
          uplinks = { };
          wanUplinkName = null;
          containerModel = {
            externalValidationDelegatedPrefixSources = {
              "fd42:dead:feed:70::/64" = "/run/secrets/access-node-ipv6-prefix-branch-hostile";
            };
            interfaces = {
              overlay-east-west = {
                containerInterfaceName = "overlay-west";
                sourceKind = "overlay";
                addresses = [ "fd42:dead:beef:ee::3/128" ];
                routes = [
                  {
                    dst = "fd42:dead:feed:70::/64";
                    proto = "overlay";
                    overlay = "east-west";
                    via6 = "fd42:dead:beef:ee::2";
                  }
                ];
              };
            };
          };
        };
    in
      if render.dynamicDelegatedRoutes == [ ] then
        true
      else
        throw ("overlay-delegated-prefix-boundary failed: network-renderer-nixos must not turn overlay-provider routes into generic s88-delegated-prefix-route services. Runtime delegated prefixes carried by Nebula/WireGuard/OpenVPN belong in the provider renderer or explicit CPM provider contract, otherwise NixOS installs an on-link route on the logical overlay veth and breaks return traffic. bad dynamicDelegatedRoutes: " + builtins.toJSON render.dynamicDelegatedRoutes)
  ' >/dev/null

echo "PASS overlay-delegated-prefix-boundary"
