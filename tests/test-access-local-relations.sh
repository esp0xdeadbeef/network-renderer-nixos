#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

nix_eval_true_or_fail "access-local-relations" env REPO_ROOT="${repo_root}" nix eval \
  --extra-experimental-features 'nix-command flakes' \
  --impure \
  --expr '
    let
      repoRoot = builtins.getEnv "REPO_ROOT";
      flake = builtins.getFlake ("path:" + repoRoot);
      lib = flake.inputs.nixpkgs.lib;
      rendered =
        import (repoRoot + "/s88/ControlModule/firewall/policy/access.nix") {
          inherit lib;
          interfaceView = {
            interfaceEntries = [
              {
                name = "tenant-users";
                sourceKind = "tenant";
              }
              {
                name = "tenant-streami";
                sourceKind = "tenant";
              }
              {
                name = "transit";
                sourceKind = "p2p";
              }
            ];
            wanNames = [ ];
          };
          communicationContract = {
            trafficTypes = [
              {
                name = "any";
                match = [ ];
              }
            ];
            relations = [
              {
                id = "allow-sitec-home-to-local-services";
                action = "allow";
                from = {
                  kind = "tenant-set";
                  members = [ "home-users" ];
                };
                to = {
                  kind = "tenant-set";
                  members = [ "streaming" ];
                };
                trafficType = "any";
              }
            ];
          };
          endpointMap.resolveEndpoint =
            endpoint:
            if builtins.isAttrs endpoint && (endpoint.kind or null) == "tenant-set" then
              map
                (name:
                  if name == "home-users" then
                    "tenant-users"
                  else if name == "streaming" then
                    "tenant-streami"
                  else
                    name)
                endpoint.members
            else
              [ ];
        };
      forwardRules = rendered.forwardRules or [ ];
      forwardPairs = rendered.forwardPairs or [ ];
    in
      builtins.elem
        "iifname \"tenant-users\" oifname \"tenant-streami\" accept comment \"allow-sitec-home-to-local-services\""
        forwardRules
      && !(builtins.elem
        "iifname \"tenant-streami\" oifname \"tenant-users\" accept comment \"allow-sitec-home-to-local-services\""
        forwardRules)
      && builtins.length forwardPairs == 2
    '

echo "PASS access-local-relations"
