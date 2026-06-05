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
      rendered =
        import (repoRoot + "/s88/ControlModule/render/containers/dns-services.nix") {
          inherit lib pkgs;
          renderedModel.runtimeTarget.services.dns = {
            listen = [ "10.20.0.1" ];
            allowFrom = [ "10.20.0.0/24" ];
            forwarders = [ "1.1.1.1" ];
            namespaceFallback = {
              defaultPublicRecursionFallback = false;
              decisions = [
                {
                  requesterScope = "tenant-a";
                  namespace = "tenant-a.lan.";
                  allowedRecordClasses = [ "A" "AAAA" ];
                  deniedRecordClasses = [ "PUBLIC-RECURSION" ];
                  failedAnswerReason = "missing-record";
                  action = "block";
                  publicRecursionFallback = false;
                  leakPrevention = "fail-closed";
                }
                {
                  requesterScope = "tenant-b";
                  namespace = "tenant-a.lan.";
                  allowedRecordClasses = [ "A" "AAAA" ];
                  deniedRecordClasses = [ "A" "AAAA" "PUBLIC-RECURSION" ];
                  failedAnswerReason = "denied-requester-scope";
                  action = "deny";
                  publicRecursionFallback = false;
                  leakPrevention = "terminal-denial";
                }
                {
                  requesterScope = "tenant-a";
                  namespace = "public.example.";
                  allowedRecordClasses = [ "A" ];
                  deniedRecordClasses = [ "NONE" ];
                  failedAnswerReason = "missing-record";
                  action = "fallback";
                  fallbackTarget = "modeled-recursive-dns";
                  publicRecursionFallback = true;
                  leakPrevention = "modeled-fallback";
                }
              ];
            };
          };
        };
      zones = rendered.services.unbound.settings.server."local-zone" or [ ];
      ok =
        builtins.elem "tenant-a.lan. static" zones
        && !(builtins.elem "public.example. static" zones);
    in
      if ok then true else throw "dns-namespace-fallback-cpm-contract failed: NixOS renderer must materialize explicit block/deny namespace fallback decisions as static local zones and must not invent zones for modeled fallback decisions"
  ' >/dev/null || {
    echo "FAIL dns-namespace-fallback-cpm-contract" >&2
    exit 1
  }

echo "PASS dns-namespace-fallback-cpm-contract"
