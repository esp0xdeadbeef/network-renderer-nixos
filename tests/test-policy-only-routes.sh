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
      render =
        import (repoRoot + "/s88/ControlModule/render/container-networks.nix") {
          inherit lib;
          containerModel = {
            interfaces = {
              overlay-east-west = {
                containerInterfaceName = "overlay-east-west";
                sourceKind = "overlay";
                addresses = [ "fd42:dead:beef:ee::2/128" ];
                routes = [
                  {
                    dst = "::/0";
                    scope = "link";
                    policyOnly = true;
                    intent.kind = "delegated-public-egress";
                  }
                ];
              };
              upstream = {
                containerInterfaceName = "upstream";
                sourceKind = "p2p";
                addresses = [ "fd42:dead:feed:1000::4/127" ];
                routes = [
                  {
                    dst = "::/0";
                    via6 = "fd42:dead:feed:1000::5";
                  }
                ];
              };
            };
          };
          uplinks = { };
          wanUplinkName = null;
        };
      overlayRoutes = render.networks."10-overlay-east-west".routes or [ ];
      hasPolicyOnlyTableRoute =
        builtins.any
          (route:
            (route.Destination or null) == "::/0"
            && (route.Scope or null) == "link"
            && (route.Table or null) == 2001)
          overlayRoutes;
      hasPolicyOnlyMainRoute =
        builtins.any
          (route:
            (route.Destination or null) == "::/0"
            && (route.Scope or null) == "link"
            && !(route ? Table))
          overlayRoutes;
    in
      if hasPolicyOnlyTableRoute && !hasPolicyOnlyMainRoute then
        true
      else
        throw "policy-only-routes failed: renderer must render CPM policyOnly routes only inside policy tables, not as main defaults. Remove this error only after delegated hostile public egress can select Nebula without turning overlay into a generic main default."
  ' >/dev/null

echo "PASS policy-only-routes"
