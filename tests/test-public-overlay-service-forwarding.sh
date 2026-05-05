#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=tests/lib/test-common.sh
source "${repo_root}/tests/lib/test-common.sh"

result_json="$(mktemp)"
stderr_file="$(mktemp)"
trap 'rm -f "$result_json" "$stderr_file"' EXIT

nix_eval_json_or_fail "public-overlay-service-forwarding" "$result_json" "$stderr_file" \
  nix eval --json --extra-experimental-features 'nix-command flakes' --impure --expr '
let
  flake = builtins.getFlake ("path:" + toString ./.);
  system = builtins.currentSystem;
  lib = flake.inputs.nixpkgs.lib;
  labs = flake.inputs.network-labs.outPath;
  hostBuild = flake.lib.renderer.buildHostFromPaths {
    selector = "s-router-hetzner-anywhere";
    inherit system;
    intentPath = labs + "/examples/s-router-public-overlay-service/intent.nix";
    inventoryPath = labs + "/examples/s-router-public-overlay-service/inventory-nixos.nix";
  };
  branchHostBuild = flake.lib.renderer.buildHostFromPaths {
    selector = "s-router-test";
    inherit system;
    intentPath = labs + "/examples/s-router-public-overlay-service/intent.nix";
    inventoryPath = labs + "/examples/s-router-public-overlay-service/inventory-nixos.nix";
  };
  container = hostBuild.renderedHost.containers."c-router-core";
  branchCoreContainer = branchHostBuild.renderedHost.containers."b-router-core-nebula";
  evaluated = flake.inputs.nixpkgs.lib.nixosSystem {
    inherit system;
    modules = [ container.config ];
  };
  branchCoreEvaluated = flake.inputs.nixpkgs.lib.nixosSystem {
    inherit system;
    modules = [ branchCoreContainer.config ];
  };
  rules = evaluated.config.networking.nftables.ruleset;
  branchCoreRules = branchCoreEvaluated.config.networking.nftables.ruleset;
  checks = {
    rendersUdpServiceDnat =
      lib.hasInfix "udp dport 4242 dnat to 10.90.10.100" rules;
    rendersTcpServiceDnat =
      lib.hasInfix "tcp dport 4242 dnat to 10.90.10.100" rules;
    preservesIntentRelationComment =
      lib.hasInfix "allow-sitec-wan-to-dmz-nebula" rules;
    allowsBranchUnderlayFromExplicitTrafficType =
      lib.hasInfix "iifname \"upstream\" meta l4proto udp udp dport 4242 accept comment \"allow-overlay-underlay-to-core\"" branchCoreRules;
  };
in
{
  ok = builtins.all (value: value == true) (builtins.attrValues checks);
  failed = lib.mapAttrsToList (name: _value: name) (lib.filterAttrs (_name: value: value != true) checks);
  inherit checks rules;
}
'

assert_json_checks_ok "public-overlay-service-forwarding" "$result_json"
pass "public-overlay-service-forwarding"
