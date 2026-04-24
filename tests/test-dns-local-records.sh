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
        runtimeTarget.services.dns = {
          listen = [ "10.20.0.1" "fd00:20::1" ];
          allowFrom = [ "10.20.0.0/24" "fd00:20::/64" ];
          forwarders = [ "1.1.1.1" "2606:4700:4700::1111" ];
          localZones = [
            {
              name = "printer.";
              type = "static";
            }
            {
              name = "home-users.";
            }
          ];
          localRecords = [
            {
              name = "test-machine-01.printer.";
              a = [ "10.20.0.10" ];
              aaaa = [ "fd00:20::10" ];
            }
            {
              name = "tv-01.home-users.";
              a = [ "10.20.0.20" ];
            }
          ];
        };
        interfaces = { };
      };
      rendered =
        import (repoRoot + "/s88/ControlModule/render/containers/dns-services.nix") {
          inherit lib pkgs renderedModel;
        };
      server = rendered.services.unbound.settings.server;
      localZones = server."local-zone" or [ ];
      localData = server."local-data" or [ ];
    in
      builtins.elem "printer. static" localZones
      && builtins.elem "home-users. static" localZones
      && builtins.elem "test-machine-01.printer. IN A 10.20.0.10" localData
      && builtins.elem "test-machine-01.printer. IN AAAA fd00:20::10" localData
      && builtins.elem "tv-01.home-users. IN A 10.20.0.20" localData
  ' >/dev/null || {
    echo "FAIL dns-local-records" >&2
    exit 1
  }

echo "PASS dns-local-records"
