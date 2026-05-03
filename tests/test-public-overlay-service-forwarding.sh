#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=tests/lib/test-common.sh
source "${repo_root}/tests/lib/test-common.sh"

# shellcheck disable=SC2016
expr='
let
  flake = builtins.getFlake ("path:" + toString ./.);
  system = builtins.currentSystem;
  labs = flake.inputs.network-labs.outPath;
  hostBuild = flake.lib.renderer.buildHostFromPaths {
    selector = "s-router-hetzner-anywhere";
    inherit system;
    intentPath = labs + "/examples/s-router-test-three-site/intent.nix";
    inventoryPath = labs + "/examples/s-router-test-three-site/inventory-nixos.nix";
  };
  container = hostBuild.renderedHost.containers."c-router-core";
  evaluated = flake.inputs.nixpkgs.lib.nixosSystem {
    inherit system;
    modules = [ container.config ];
  };
  rules = evaluated.config.networking.nftables.ruleset;
  lib = flake.inputs.nixpkgs.lib;
in
  lib.hasInfix "udp dport 4242 dnat to 10.90.10.100" rules
  && lib.hasInfix "tcp dport 4242 dnat to 10.90.10.100" rules
  && lib.hasInfix "allow-sitec-wan-to-dmz-nebula" rules
'

if nix eval --extra-experimental-features 'nix-command flakes' --impure --expr "$expr" | grep -qx true; then
  pass "public-overlay-service-forwarding"
else
  fail "public overlay service forwarding did not render expected DNAT"
fi
