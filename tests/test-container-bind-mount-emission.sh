#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${repo_root}/tests/lib/test-common.sh"

nix_eval_true_or_fail \
  container-bind-mount-emission \
  env REPO_ROOT="${repo_root}" \
    nix eval \
    --extra-experimental-features 'nix-command flakes' \
    --impure --expr '
      let
        repoRoot = builtins.getEnv "REPO_ROOT";
        flake = builtins.getFlake ("path:" + repoRoot);
        lib = flake.inputs.nixpkgs.lib;
        emitted =
          import (repoRoot + "/s88/ControlModule/render/containers/emission.nix") {
            inherit lib;
            debugEnabled = false;
            deploymentHostName = "host";
            containerName = "router";
            firewallArg = { enable = false; };
            alarmModel = { };
            uplinks = { };
            wanUplinkName = null;
            renderedModel = {
              bindMounts = {
                "" = {
                  hostPath = "";
                  isReadOnly = true;
                };
                "/run/secrets/prefix" = {
                  hostPath = "/run/secrets/prefix";
                  isReadOnly = true;
                };
              };
              interfaces = { };
              site.tenantPrefixOwners = {
                "6|source:/run/secrets/access-node-ipv6-prefix-router-access-hostile".owner =
                  "router-access-hostile";
              };
            };
          };
      in
        !(emitted.bindMounts ? "")
        && (emitted.bindMounts."/run/secrets/prefix".hostPath or null) == "/run/secrets/prefix"
        && (emitted.bindMounts."/run/secrets/access-node-ipv6-prefix-router-access-hostile".hostPath or null)
          == "/run/secrets/access-node-ipv6-prefix-router-access-hostile"
    '

echo "PASS container-bind-mount-emission"
