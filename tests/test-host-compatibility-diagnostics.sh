#!/usr/bin/env bash
# GAMP-ID: FS-970-HDS-010-SDS-020-SMS-040
# GAMP-ID: FS-982-HDS-010-SDS-010-SMS-130
# GAMP-SCOPE: software-module-test
set -euo pipefail

repo_root="${NETWORK_RENDERER_NIXOS_ROOT:-$(git -C "$(dirname "${BASH_SOURCE[0]}")" rev-parse --show-toplevel)}"

REPO_ROOT="${repo_root}" nix eval --impure --raw --expr '
  let
    repoRoot = builtins.getEnv "REPO_ROOT";
    flake = builtins.getFlake ("path:" + repoRoot);
    lib = flake.inputs.nixpkgs.lib;
    diagnose = config: vmNicHandled:
      import (repoRoot + "/s88/ControlModule/render/host-compatibility-diagnostics.nix") {
        inherit lib config vmNicHandled;
      };
    compatibility = diagnose {
      systemd.services."gen-kea-vlan2".serviceConfig.ExecStartPost = [ "opaque-command" ];
      virtualisation.qemu.networkingOptions = [ "opaque-local-option" ];
    } false;
    canonical = diagnose {
      systemd.services."gen-kea-vlan2".serviceConfig.ExecStart = "renderer-owned-generator";
      virtualisation.qemu.networkingOptions = [ "renderer-owned-option" ];
    } true;
    messages = builtins.concatStringsSep "\n" compatibility.warnings;
    require = condition: message: if condition then true else throw message;
  in
    if
      require (builtins.length compatibility.warnings == 2)
        "host-local compatibility ownership did not produce both renderer warnings"
      && require (lib.hasInfix "RUNTIME_RESERVATION_SOURCE_OUTSIDE_CPM" messages)
        "reservation compatibility warning lost its controlled code"
      && require (lib.hasInfix "VM_NIC_PLATFORM_BINDING_MISSING" messages)
        "VM NIC compatibility warning lost its controlled code"
      && require (canonical.warnings == [ ])
        "canonical renderer-owned composition produced a compatibility warning"
      && require (!lib.hasInfix "opaque-command" messages && !lib.hasInfix "opaque-local-option" messages)
        "diagnostics leaked host-local material"
    then "ok" else throw "unreachable"
' >/dev/null

echo "PASS renderer host compatibility diagnostics"
