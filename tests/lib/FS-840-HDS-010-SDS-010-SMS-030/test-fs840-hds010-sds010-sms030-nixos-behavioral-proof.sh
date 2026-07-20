#!/usr/bin/env bash
# GAMP-ID: FS-840-HDS-010-SDS-010-SMS-030
# GAMP-SCOPE: software-module-test
# Focused construction test: Behavioral proof — nix eval of renderer
# hostModule verifying generated systemd unit after=["sops-nix.service"].
#
# SMS-030: The NixOS renderer must reject service readiness when required
# secret material is missing or stale. In NixOS, this is implemented via
# systemd ordering: container@<name>.after = [ "sops-nix.service" ].
#
# This behavioral test invokes the renderer's hostModule with real CPM
# output (built from example intent/inventory fixtures) and verifies
# that every generated container has a corresponding systemd service
# with sops-nix.service in its after= list.
#
# Behavioral proof (not scanner/grep): uses nix eval --impure with
# builtins.getFlake to exercise the actual renderer code path.
#
# Companion scanner test: test-fs840-hds010-sds010-sms030-nixos-secret-material-readiness-rejection.sh
#
# Auto-discovered by tests/test.sh via glob test-*.sh.
set -euo pipefail

repo_root="${SMS_TEST_REPO_ROOT:-$(git -C "$(dirname "${BASH_SOURCE[0]}")" rev-parse --show-toplevel)}"
source "${repo_root}/tests/lib/test-common.sh"

example_root="${repo_root}/tests/fixtures/s-router-overlay-dns-lane-policy"

echo "--- FS-840-HDS-010-SDS-010-SMS-030: Behavioral proof — sops-nix.service ordering ---"
echo ""

# ============================================================
# Behavioral Proof: Invoke hostModule with real CPM output
# and verify systemd.services."container@<name>".after
# contains "sops-nix.service" for every container.
# ============================================================

nix_eval_true_or_fail "FS-840-HDS-010-SDS-010-SMS-030 behavioral: container@ sops-nix ordering" \
  env REPO_ROOT="${repo_root}" \
  INTENT_PATH="${example_root}/intent.nix" \
  INVENTORY_PATH="${example_root}/inventory-nixos.nix" \
  nix eval \
    --extra-experimental-features 'nix-command flakes' \
    --impure --expr '
      let
        flake = builtins.getFlake ("path:" + builtins.getEnv "REPO_ROOT");
        lib = flake.inputs.nixpkgs.lib;

        # Build CPM from example intent/inventory fixtures
        cpmFlake = flake.inputs.network-control-plane-model;
        cpm = cpmFlake.lib.x86_64-linux.compileAndBuildFromPaths {
          inputPath = builtins.getEnv "INTENT_PATH";
          inventoryPath = builtins.getEnv "INVENTORY_PATH";
          validateForwardingModel = false;
          validateRuntimeModel = false;
        };

        # Build host from CPM to get containers and hostName
        hostBuild = flake.lib.renderer.buildHostFromControlPlane {
          controlPlaneOut = cpm;
          selector = "s-router-test";
          system = "x86_64-linux";
        };

        # Get deployment host name from CPM
        deploymentHosts = cpm.deploymentHosts or { };
        deploymentHostNames = builtins.attrNames deploymentHosts;
        hostName = if deploymentHostNames != [ ]
          then builtins.head deploymentHostNames
          else "s-router-test";

        # Invoke hostModule — the actual renderer code path
        pkgs = flake.inputs.nixpkgs.legacyPackages.x86_64-linux;
        moduleFn = flake.lib.renderer.hostModule {
          inherit lib;
          inherit hostName;
          cpm = cpm;
          system = "x86_64-linux";
        };

        # Call the module function to get the generated attrset
        moduleResult = moduleFn {
          inherit lib;
          inherit pkgs;
          config = { };
        };

        # Extract systemd services and containers
        services = moduleResult.systemd.services or { };
        containers = moduleResult.containers or { };
        containerNames = builtins.attrNames containers;

        # Verify: every container has a corresponding systemd service
        # with after = [ "sops-nix.service" ]
        containerServiceNames = map (name: "container@${name}") containerNames;

        allHaveService = builtins.all
          (svcName: builtins.hasAttr svcName services)
          containerServiceNames;

        # Verify each container service has sops-nix.service in after=
        allHaveSopsAfter = builtins.all
          (svcName:
            let
              svc = builtins.getAttr svcName services;
              afterList = svc.after or [ ];
            in
              builtins.elem "sops-nix.service" afterList
          )
          containerServiceNames;

        # Results
        checks = {
          hasContainers = containerNames != [ ];
          allContainerServicesExist = allHaveService;
          allHaveSopsNixAfter = allHaveSopsAfter;
          containerCount = builtins.length containerNames;
          serviceCount = builtins.length (builtins.attrNames services);
        };
      in
        checks.hasContainers
        && checks.allContainerServicesExist
        && checks.allHaveSopsNixAfter
        && builtins.trace "FS-840-HDS-010-SDS-010-SMS-030 behavioral: ${toString checks.containerCount} container(s), all have container@ with after=[\"sops-nix.service\"]" true
    '

echo "PASS FS-840-HDS-010-SDS-010-SMS-030 behavioral proof: container@ sops-nix.service ordering verified via nix eval"
exit 0
