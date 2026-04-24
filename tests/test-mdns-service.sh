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
        runtimeTarget.services.mdns = {
          reflector = true;
          allowInterfaces = [ "tenant-home-users" "tenant-streaming" ];
          publish = {
            enable = false;
            addresses = false;
          };
        };
      };
      rendered =
        import (repoRoot + "/s88/ControlModule/render/containers/mdns-services.nix") {
          inherit lib pkgs renderedModel;
        };
      avahi = rendered.services.avahi;
    in
      avahi.enable
      && avahi.reflector
      && avahi.allowInterfaces == [ "tenant-home-users" "tenant-streaming" ]
      && !(avahi.publish.enable or true)
      && !(avahi.publish.addresses or true)
  ' >/dev/null || {
    echo "FAIL mdns-service" >&2
    exit 1
  }

echo "PASS mdns-service"
