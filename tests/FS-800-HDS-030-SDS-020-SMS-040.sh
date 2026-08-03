#!/usr/bin/env bash
# GAMP-ID: FS-800-HDS-030-SDS-020-SMS-040
# GAMP-SCOPE: software-module-test
set -euo pipefail

repo_root="${NETWORK_RENDERER_NIXOS_ROOT:-$(git -C "$(dirname "${BASH_SOURCE[0]}")" rev-parse --show-toplevel)}"

REPO_ROOT="${repo_root}" nix eval --impure --raw --expr '
  let
    repoRoot = builtins.getEnv "REPO_ROOT";
    flake = builtins.getFlake ("path:" + repoRoot);
    lib = flake.inputs.nixpkgs.lib;
    contract = {
      value = 1492;
      source = "inventory-runtime-service";
      sourceService = "pppoe-client";
      sourceTarget = "core";
      sourceInterface = "wan";
      sourceRuntimeInterface = "ppp0";
    };
    baseScope = {
      fileStem = "test";
      interfaceName = "lan2";
      delegatedPrefix = null;
      prefixes = [ "fd42:1::/64" ];
      rdnss = [ ];
      domain = "lan.";
      managed = false;
      otherConfig = false;
      onLink = true;
      autonomous = true;
    };
    render = scope: import (repoRoot + "/s88/ControlModule/access/render/ra-path-mtu.nix") { inherit scope; };
    nominal = render (baseScope // { pathMtu = contract; });
    missing = render (baseScope // { delegatedPrefix.sourceFile = "/run/secrets/prefix"; });
    diagnosed = render (baseScope // {
      delegatedPrefix.sourceFile = "/run/secrets/prefix";
      pathMtuDiagnostic = {
        traceId = "FS-800-HDS-030-SDS-020-SMS-040";
        code = "ACCESS_RA_PATH_MTU_AMBIGUOUS";
        sourceLayer = "inventory";
        message = "Multiple explicit sources";
      };
    });
    invalid = builtins.tryEval (render (baseScope // { pathMtu = contract // { value = 1279; }; })).directive;
    mockPkgs = {
      writeShellScript = _name: text: text;
      iproute2 = "/nix/store/mock-iproute2";
      gnugrep = "/nix/store/mock-gnugrep";
      python3 = "/nix/store/mock-python3";
      radvd = "/nix/store/mock-radvd";
      coreutils = "/nix/store/mock-coreutils";
      gnused = "/nix/store/mock-gnused";
      systemd = "/nix/store/mock-systemd";
    };
    module = import (repoRoot + "/s88/ControlModule/access/render/radvd.nix") {
      inherit lib;
      pkgs = mockPkgs;
      scope = baseScope // { pathMtu = contract; };
    };
    generated = module.systemd.services."radvd-generate-test".serviceConfig.ExecStart;
    require = condition: message: if condition then true else throw message;
  in
  if
    require (nominal.pathMtu == 1492 && nominal.directive == "AdvLinkMTU 1492;" && nominal.warnings == [ ])
      "renderer lost the explicit RA path MTU"
    && require (lib.hasInfix "AdvLinkMTU 1492;" generated)
      "radvd generator did not own AdvLinkMTU"
    && require (builtins.length missing.warnings == 1 && lib.hasInfix "ACCESS_RA_PATH_MTU_MISSING" (builtins.head missing.warnings))
      "missing inventory path MTU did not produce a renderer warning"
    && require (builtins.length diagnosed.warnings == 1 && lib.hasInfix "ACCESS_RA_PATH_MTU_AMBIGUOUS" (builtins.head diagnosed.warnings))
      "CPM ambiguity diagnostic was not projected by the renderer"
    && require (!invalid.success)
      "invalid IPv6 path MTU was accepted"
  then "ok" else throw "unreachable"
' >/dev/null

echo "PASS FS-800-HDS-030-SDS-020-SMS-040 renderer RA path-MTU materialization"
