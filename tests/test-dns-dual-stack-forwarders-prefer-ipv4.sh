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
      render = dns:
        import (repoRoot + "/s88/ControlModule/render/containers/dns-services.nix") {
          inherit lib pkgs;
          renderedModel = {
            runtimeTarget.services.dns = dns;
            interfaces.transit = {
              sourceKind = "p2p";
              addresses = [ "10.99.0.2/31" "fd00:99::2/127" ];
              containerInterfaceName = "transit";
            };
          };
        };
      baseDns = {
        listen = [ "10.90.10.1" "fd42:dead:cafe:10::1" ];
        allowFrom = [ "10.90.10.0/24" "fd42:dead:cafe:10::/64" ];
      };
      mixed = (render (baseDns // { forwarders = [ "1.1.1.1" "2606:4700:4700::1111" ]; })).services.unbound.settings.server;
      v4Only = (render (baseDns // { forwarders = [ "1.1.1.1" "9.9.9.9" ]; })).services.unbound.settings.server;
      v6Only = (render (baseDns // { forwarders = [ "2606:4700:4700::1111" "2620:fe::fe" ]; })).services.unbound.settings.server;
      ok =
        (mixed."prefer-ip4" or false) == true
        && !(v4Only ? "prefer-ip4")
        && !(v6Only ? "prefer-ip4");
    in
      if ok then true else throw "dns-dual-stack-forwarders-prefer-ipv4 failed: mixed IPv4/IPv6 public forwarders must prefer IPv4 so one broken IPv6 egress path cannot stall Unbound while healthy IPv4 forwarders exist"
  ' >/dev/null || {
    echo "FAIL dns-dual-stack-forwarders-prefer-ipv4" >&2
    exit 1
  }

echo "PASS dns-dual-stack-forwarders-prefer-ipv4"
