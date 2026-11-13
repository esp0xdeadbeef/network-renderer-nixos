#!/usr/bin/env bash
# GAMP-ID: FS-310-HDS-010-SDS-010-SMS-130
# GAMP-SCOPE: software-module-test
#
# A forwarding sysctl has exactly one resolved value per host and per container.
#
# FS-310-HDS-010-SDS-010-SMS-130 forbids a renderer adding a kernel sysctl that
# changes forwarding behavior without canonical authority. The inverse is just
# as important and is what this case pins: the renderer's own writers must
# *compose*, not collide. `boot.kernel.sysctl` is a unique option per priority
# tier, so a baseline written at the same priority as a feature claim (or a
# feature module restating a claim it already made) makes NixOS fail with
# "defined multiple times while it's expected to be unique" and no host builds
# at all. That is a renderer defect, not a host defect.
#
# The observed regression: `profiles/common-router.nix` wrote
# `net.ipv4.ip_forward` as a plain value while `flake.nix` and
# `module/dns-validation-authority.nix` wrote it with `lib.mkDefault`, and
# `dns-validation-authority` also restated `net.ipv6.conf.all.forwarding`
# inside its forwarding-gateway branch. Every one of those is a definition at
# the same tier, so the option merge threw for every host that imported more
# than one of them.
set -euo pipefail

repo_root="${SMS_TEST_REPO_ROOT:-$(git -C "$(dirname "${BASH_SOURCE[0]}")" rev-parse --show-toplevel)}"

echo "--- FS-310-HDS-010-SDS-010-SMS-130: forwarding sysctl has a single writer ---"

# --- Source contract: the baseline sits below the feature claims ---
# A plain definition and `lib.mkDefault` both land in a tier a peer writer can
# share. The baseline must be strictly below `mkDefault` so a module that
# asserts forwarding from its own authority always wins, whatever else is
# imported alongside it.
baseline="$(cat "${repo_root}/s88/ControlModule/profiles/common-router.nix")"

if grep -qE '"net\.ipv4\.ip_forward" *= *1;' <<<"${baseline}"; then
  echo "FAIL: common-router declares net.ipv4.ip_forward as a plain definition;" \
    "that ties with every feature module's mkDefault and duplicates the option" >&2
  exit 1
fi
if grep -qE '"net\.ipv4\.ip_forward" *= *lib\.mkDefault' <<<"${baseline}"; then
  echo "FAIL: common-router declares net.ipv4.ip_forward with lib.mkDefault;" \
    "the router baseline must sit below mkDefault so a feature claim wins" >&2
  exit 1
fi
grep -qE '"net\.ipv4\.ip_forward" *= *lib\.mkOverride 1500' <<<"${baseline}"
echo "PASS: common-router declares the IPv4 forwarding baseline below mkDefault"

# --- Source contract: the forwarding gateway does not replace the sysctl set ---
# `dns-validation-authority.nix` merges its forwarding-gateway branch with plain
# `//`. Writing a `boot.kernel.sysctl` *attrset* there replaced every sysctl the
# module declared above it. Each claim must be its own option path so the module
# system merges them and gating is `lib.mkIf`, not a competing definition.
dns_authority="${repo_root}/s88/ControlModule/module/dns-validation-authority.nix"
if grep -qE '^ *boot\.kernel\.sysctl = \{' "${dns_authority}"; then
  echo "FAIL: dns-validation-authority writes a boot.kernel.sysctl attrset;" \
    "merged with // it replaces the other sysctls this module declares" >&2
  exit 1
fi
echo "PASS: dns-validation-authority declares forwarding as option paths"

# --- Behaviour contract: the real writers compose to one resolved value ---
# Compose the baseline, a DNS forwarding gateway and the public-ingress force in
# one module system at their real priorities and read the merged value back. If
# any two writers tie, this evaluation throws instead of returning a value.
echo "--- Behaviour: baseline + forwarding gateway + public ingress resolve ---"
resolved="$(env REPO_ROOT="${repo_root}" nix eval \
  --extra-experimental-features 'nix-command flakes' \
  --impure --json --expr '
    let
      repoRoot = builtins.getEnv "REPO_ROOT";
      flake = builtins.getFlake ("path:" + repoRoot);
      lib = flake.inputs.nixpkgs.lib;

      # A real NixOS evaluation, so the option declarations and the sysctl
      # merge are exactly the ones a host uses.
      baseline = import (repoRoot + "/s88/ControlModule/profiles/common-router.nix") {
        inherit lib;
        pkgs = flake.inputs.nixpkgs.legacyPackages.x86_64-linux;
      };

      # The two claims the renderer makes from its own authority. Written here
      # at the same priorities those modules use, so a tier collision is
      # reproduced rather than papered over.
      featureClaims = {
        boot.kernel.sysctl = {
          "net.ipv4.ip_forward" = lib.mkDefault 1;
          "net.ipv6.conf.all.forwarding" = lib.mkDefault 1;
        };
      };
      forcedClaim = {
        boot.kernel.sysctl."net.ipv4.ip_forward" = lib.mkForce true;
      };

      evaluated = (import (flake.inputs.nixpkgs + "/nixos/lib/eval-config.nix") {
        system = "x86_64-linux";
        modules = [ baseline featureClaims forcedClaim ];
      }).config.boot.kernel.sysctl;
    in
      {
        ipv4 = evaluated."net.ipv4.ip_forward";
        ipv6 = evaluated."net.ipv6.conf.all.forwarding";
      }
  ')"

ipv4="$(jq -r '.ipv4' <<<"${resolved}")"
ipv6="$(jq -r '.ipv6' <<<"${resolved}")"

# The force outranks the baseline and the default: the host forwards.
case "${ipv4}" in
  true|1) ;;
  *)
    echo "FAIL: merged net.ipv4.ip_forward is '${ipv4}', expected the forced claim to win" >&2
    exit 1
    ;;
esac
case "${ipv6}" in
  1) ;;
  *)
    echo "FAIL: merged net.ipv6.conf.all.forwarding is '${ipv6}', expected 1" >&2
    exit 1
    ;;
esac
echo "PASS: baseline, forwarding gateway and public ingress compose to one value"
echo "PASS: FS-310-HDS-010-SDS-010-SMS-130 forwarding sysctl single writer"
