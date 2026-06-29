#!/usr/bin/env bash
# GAMP-ID: FS-982-HDS-010-SDS-010-SMS-010
# GAMP-SCOPE: software-module-test
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${repo_root}/tests/lib/test-common.sh"

nix_eval_true_or_fail "FS-982 host with no router runtime units renders no router containers" \
  env REPO_ROOT="${repo_root}" \
    nix eval \
      --extra-experimental-features 'nix-command flakes' \
      --impure --expr '
        let
          repoRoot = builtins.getEnv "REPO_ROOT";
          flake = builtins.getFlake ("path:" + repoRoot);
          lib = flake.inputs.nixpkgs.lib;
          system = "x86_64-linux";
          cpm = rec {
            control_plane_model = {
              meta.traceId = "test-host-without-router-units";
              deployment.hosts.s-router-test-clients = {
                accessHandoff = {
                  kind = "pppoe";
                  server = "emulated-isp";
                };
                uplinks = { };
              };
              render.hosts.s-router-test-clients.deploymentHost = "s-router-test-clients";
              realization.nodes = { };
              data.active-lab.test-clients = {
                enterprise = "active-lab";
                siteName = "test-clients";
                runtimeTargets = { };
                endpointAssignment = { };
              };
            };
            deploymentHosts = control_plane_model.deployment.hosts;
            realization = control_plane_model.realization;
            render = control_plane_model.render;
          };
          module = flake.lib.renderer.hostModule {
            inherit lib system;
            hostName = "s-router-test-clients";
            cpm = cpm;
            selectorFile = "tests/test-fs982-hds010-sds010-sms010-host-without-router-units-noop.sh";
          };
          evaluated = lib.nixosSystem {
            inherit system;
            modules = [ module ];
          };
          controlPlane = builtins.fromJSON evaluated.config.environment.etc."network-artifacts/control-plane.json".text;
          renderedHost = builtins.fromJSON evaluated.config.environment.etc."network-artifacts/rendered-host.json".text;
          require = cond: msg: if cond then true else throw msg;
        in
          require (builtins.attrNames evaluated.config.containers == [ ])
            "client-only deployment host must not render router containers"
          && require (renderedHost.selectedUnits == [ ])
            "client-only deployment host must preserve empty selectedUnits in rendered artifact"
          && require (builtins.attrNames (renderedHost.containers or { }) == [ ])
            "client-only rendered artifact must report zero router containers"
          && require ((controlPlane.deploymentHosts.s-router-test-clients.accessHandoff.kind or null) == "pppoe")
            "client-only deployment host must preserve explicit accessHandoff data"
      '

echo "PASS FS-982 host with no router runtime units renders no router containers"
