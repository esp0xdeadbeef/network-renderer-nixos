#!/usr/bin/env bash
set -euo pipefail
# GAMP-ID: FS-370-HDS-010-SDS-010-SMS-120
# GAMP-ID: FS-350-HDS-040-SDS-010-SMS-030

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${repo_root}/tests/lib/test-common.sh"

example_root="${repo_root}/tests/fixtures/s-router-overlay-dns-lane-policy"

# FS-370: "every source prefix that may leave a site" binds to the exit that may
# carry it, realized "as exactly one preferred-source default per address family
# on the modeled deterministic route to the selected exit". FS-370-HDS-010-
# SDS-010-SMS-120 is the NixOS renderer item for materializing those per-lane
# routes/rules; the control plane publishes the binding
# (FS-370-HDS-010-SDS-010-SMS-050 `candidateEgress.backingRef.lane`), so the
# renderer consumes it and never re-derives it (FS-171).
nix_eval_true_or_fail "runtime-origin-loopback-egress-render" env \
  REPO_ROOT="${repo_root}" \
  INTENT_PATH="${example_root}/intent.nix" \
  INVENTORY_PATH="${example_root}/inventory-nixos.nix" \
  nix eval \
    --extra-experimental-features 'nix-command flakes' \
    --impure --expr "import ${repo_root}/tests/nix/fs370-runtime-origin-egress.nix"

# The renderer's runtime-origin firewall contract: a canonical forwarding rule
# that names the runtime-origin source emits a source-scoped accept pair, and
# the source comes from the model's binding (not from a renderer-local guess).
nix_eval_true_or_fail "runtime-origin-loopback-egress-firewall" env \
  REPO_ROOT="${repo_root}" \
  INTENT_PATH="${example_root}/intent.nix" \
  INVENTORY_PATH="${example_root}/inventory-nixos.nix" \
  nix eval \
    --extra-experimental-features 'nix-command flakes' \
    --impure --expr '
      let
        repoRoot = builtins.getEnv "REPO_ROOT";
        flake = builtins.getFlake ("path:" + repoRoot);
        lib = flake.inputs.nixpkgs.lib;
        built = import (repoRoot + "/tests/nix/build-host-from-paths.nix") {
          selector = "s-router-test";
          system = "x86_64-linux";
          intentPath = builtins.getEnv "INTENT_PATH";
          inventoryPath = builtins.getEnv "INVENTORY_PATH";
        };
        targets =
          lib.concatMap
            (enterprise: lib.concatMap (site: builtins.attrValues (site.runtimeTargets or { })) (builtins.attrValues enterprise))
            (builtins.attrValues built.controlPlaneOut.control_plane_model.data);
        bound =
          builtins.head
            (builtins.filter
              (target:
                (target.runtimeOriginEgress.enabled or false) == true
                && builtins.isString ((target.runtimeOriginEgress.preferredSources or { }).ipv4 or null))
              targets);
        v4 = bound.runtimeOriginEgress.preferredSources.ipv4;
        v6 = bound.runtimeOriginEgress.preferredSources.ipv6;
        forwarding =
          import (repoRoot + "/s88/ControlModule/firewall/lookup/forwarding-intent.nix") {
            lib = lib;
            runtimeTarget.forwardingIntent = {
              mode = "explicit-access-forwarding";
              rules = [
                {
                  action = "accept";
                  fromInterface = "core-nebula";
                  toInterface = "transit";
                  relationId = "runtime-origin-egress";
                  sourcePrefixes = [
                    { family = 4; prefix = "${v4}/32"; }
                    { family = 6; prefix = "${v6}/128"; }
                  ];
                }
              ];
            };
            interfaces = {
              core-nebula.containerInterfaceName = "core-nebula";
              transit.containerInterfaceName = "transit";
            };
          };
        rules =
          import (repoRoot + "/s88/ControlModule/firewall/emission/default.nix") {
            lib = lib;
          } {
            tableName = "router";
            forwardPolicy = "drop";
            forwardPairs = forwarding.accessForwardPairs;
          };
      in
        lib.hasInfix
          "iifname \"core-nebula\" oifname \"transit\" ip saddr ${v4}/32 accept comment \"runtime-origin-egress\""
          rules
        && lib.hasInfix
          "iifname \"core-nebula\" oifname \"transit\" ip6 saddr ${v6}/128 accept comment \"runtime-origin-egress\""
          rules
    '

pass "runtime-origin-loopback-egress-render"
