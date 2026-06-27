#!/usr/bin/env bash
# GAMP-ID: FS-370-HDS-010-SDS-010-SMS-120
# GAMP-SCOPE: software-module-test
# Focused construction test: NixOS renderer per-lane return-path routing.
#
# SMS-120: NixOS Materialization — FS-370 Per-Lane Return-Path Routing.
# Verifies the NixOS renderer generates nixos-module attributes for:
#   - nftables forward rules with per-lane path-label comments
#   - ip route entries for return-path subnets
#   - ip rule entries for policy routing on shared interfaces
#
# Uses mock CPM fixture to invoke hostModule and verify generated
# nixos-module output contains expected artifacts.
#
# Seeded negatives verify error detection for:
#   N1: Missing per-lane ip rule on policy DS
#   N2: DS reverse forward rule absent
#   N3: Default-route catch-all on shared interface
#   N4: Return-path route to wrong interface
#
# Auto-discovered by tests/test.sh via glob test-*.sh.
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${repo_root}/tests/lib/test-common.sh"

fixture_dir="${repo_root}/tests/fixtures/s-router-overlay-dns-lane-policy"
intent_path="${fixture_dir}/intent.nix"
inventory_path="${fixture_dir}/inventory-nixos.nix"

all_checks_passed=true

echo "--- FS-370-HDS-010-SDS-010-SMS-120: NixOS per-lane return-path routing ---"
echo ""

# ============================================================
# Predicate 1: ip rules exist with To=<tenant-subnet> for
# DS-facing tenant subnets on policy node interfaces.
# ============================================================
echo "--- Predicate 1: Per-lane ip rules with To=<tenant-subnet> ---"

nix_eval_true_or_fail "FS-370-HDS-010-SDS-010-SMS-120 P1: per-lane ip rules" \
  env REPO_ROOT="${repo_root}" \
    INTENT_PATH="${intent_path}" \
    INVENTORY_PATH="${inventory_path}" \
  nix eval \
    --extra-experimental-features 'nix-command flakes' \
    --impure --expr '
      let
        flake = builtins.getFlake ("path:" + builtins.getEnv "REPO_ROOT");
        lib = flake.inputs.nixpkgs.lib;
        repoRoot = builtins.getEnv "REPO_ROOT";
        intentPath = builtins.getEnv "INTENT_PATH";
        inventoryPath = builtins.getEnv "INVENTORY_PATH";

        cpmFlake = flake.inputs.network-control-plane-model;
        cpm = cpmFlake.lib.x86_64-linux.compileAndBuildFromPaths {
          inputPath = intentPath;
          inherit inventoryPath;
          validateForwardingModel = false;
          validateRuntimeModel = false;
        };

        hostBuild = flake.lib.renderer.buildHostFromControlPlane {
          controlPlaneOut = cpm;
          selector = "s-router-test";
          system = "x86_64-linux";
        };

        containers = hostBuild.renderedHost.containers or {};

        # Check DS node for per-lane ip rules
        ds = containers."s-router-downstream-selector" or {};
        pkgs = flake.inputs.nixpkgs.legacyPackages.x86_64-linux;
        dsCfg = (lib.nixosSystem {
          system = "x86_64-linux";
          modules = [ (ds.config or {}) ];
        }).config;
        dsNetworks = dsCfg.systemd.network.networks or {};
        dsRules = builtins.concatLists
          (map (n: (dsNetworks.${n}.routingPolicyRules or []))
            (builtins.attrNames dsNetworks));

        # Rules with To= prefix are destination-scoped (ip rule add to <subnet>)
        destinationRules = builtins.filter
          (r: builtins.hasAttr "To" r) dsRules;

        # Should have destination rules for known tenant subnets
        hasAdminRules = builtins.any
          (r: builtins.match "10.20.15.*" (r.To or "") != null)
          destinationRules;
        hasClientRules = builtins.any
          (r: builtins.match "10.20.20.*" (r.To or "") != null)
          destinationRules;

        # Check policy node too
        policy = containers."s-router-policy-only" or {};
        policyCfg = (lib.nixosSystem {
          system = "x86_64-linux";
          modules = [ (policy.config or {}) ];
        }).config;
        policyNetworks = policyCfg.systemd.network.networks or {};
        policyRules = builtins.concatLists
          (map (n: (policyNetworks.${n}.routingPolicyRules or []))
            (builtins.attrNames policyNetworks));
        policyDestinationRules = builtins.filter
          (r: builtins.hasAttr "To" r) policyRules;
        policyHasDestinationRules = builtins.length policyDestinationRules > 0;

        hasDestinationRulesOnDS = builtins.length destinationRules > 0;
      in
        hasDestinationRulesOnDS
        && hasAdminRules
        && hasClientRules
        && policyHasDestinationRules
        && builtins.trace "FS-370-HDS-010-SDS-010-SMS-120 P1: ${toString (builtins.length destinationRules)} destination rules on DS, ${toString (builtins.length policyDestinationRules)} on policy" true
    '

echo "PASS P1: Per-lane ip rules with To=<tenant-subnet> exist"

# ============================================================
# Predicate 2: nftables forward chain has per-lane accept rules
# with policy drop default.
# ============================================================
echo ""
echo "--- Predicate 2: nftables forward chain with per-lane accept rules ---"

nix_eval_true_or_fail "FS-370-HDS-010-SDS-010-SMS-120 P2: nftables forward rules" \
  env REPO_ROOT="${repo_root}" \
    INTENT_PATH="${intent_path}" \
    INVENTORY_PATH="${inventory_path}" \
  nix eval \
    --extra-experimental-features 'nix-command flakes' \
    --impure --expr '
      let
        flake = builtins.getFlake ("path:" + builtins.getEnv "REPO_ROOT");
        lib = flake.inputs.nixpkgs.lib;
        repoRoot = builtins.getEnv "REPO_ROOT";
        intentPath = builtins.getEnv "INTENT_PATH";
        inventoryPath = builtins.getEnv "INVENTORY_PATH";

        cpmFlake = flake.inputs.network-control-plane-model;
        cpm = cpmFlake.lib.x86_64-linux.compileAndBuildFromPaths {
          inputPath = intentPath;
          inherit inventoryPath;
          validateForwardingModel = false;
          validateRuntimeModel = false;
        };

        hostBuild = flake.lib.renderer.buildHostFromControlPlane {
          controlPlaneOut = cpm;
          selector = "s-router-test";
          system = "x86_64-linux";
        };

        containers = hostBuild.renderedHost.containers or {};
        ds = containers."s-router-downstream-selector" or {};
        pkgs = flake.inputs.nixpkgs.legacyPackages.x86_64-linux;
        dsCfg = (lib.nixosSystem {
          system = "x86_64-linux";
          modules = [ (ds.config or {}) ];
        }).config;

        nftEnabled = dsCfg.networking.nftables.enable or false;
        ruleset = if nftEnabled then dsCfg.networking.nftables.ruleset or "" else "";

        # Forward chain should have policy drop
        hasForwardDrop = builtins.match ".*chain forward.*policy drop.*" ruleset != null;

        # Should have reverse accept rules (policy-facing -> access-facing)
        hasReverseRules = builtins.match ".*iifname.*policy-.*oifname.*access-.*accept.*" ruleset != null;

        # Should have forward rules (access-facing -> policy-facing)
        hasForwardRules = builtins.match ".*iifname.*access-.*oifname.*policy-.*accept.*" ruleset != null;
        hasForwardPathComment =
          lib.hasInfix "comment \"selector-handoff-forward--s-router-access-client--access-to-selector-to-selector-to-policy--fabric\"" ruleset;
        hasReversePathComment =
          lib.hasInfix "comment \"selector-handoff-reverse--s-router-access-client--selector-to-policy-to-access-to-selector--fabric\"" ruleset;
        noAmbiguousNoUplinkComment = !(lib.hasInfix "no-uplink" ruleset);
      in
        nftEnabled
        && hasForwardDrop
        && hasReverseRules
        && hasForwardRules
        && hasForwardPathComment
        && hasReversePathComment
        && noAmbiguousNoUplinkComment
        && builtins.trace "FS-370-HDS-010-SDS-010-SMS-120 P2: nftables enabled=${builtins.toJSON nftEnabled}, forwardDrop=${builtins.toJSON hasForwardDrop}, reverse=${builtins.toJSON hasReverseRules}, pathComments=${builtins.toJSON (hasForwardPathComment && hasReversePathComment)}" true
    '

echo "PASS P2: nftables forward chain has per-lane accept rules with policy drop and path-label comments"

# ============================================================
# Predicate 3: No "to 0.0.0.0/0" catch-all rules on shared
# source interfaces.
# ============================================================
echo ""
echo "--- Predicate 3: No default-route catch-all on shared interfaces ---"

nix_eval_true_or_fail "FS-370-HDS-010-SDS-010-SMS-120 P3: no catch-all rules" \
  env REPO_ROOT="${repo_root}" \
    INTENT_PATH="${intent_path}" \
    INVENTORY_PATH="${inventory_path}" \
  nix eval \
    --extra-experimental-features 'nix-command flakes' \
    --impure --expr '
      let
        flake = builtins.getFlake ("path:" + builtins.getEnv "REPO_ROOT");
        lib = flake.inputs.nixpkgs.lib;
        repoRoot = builtins.getEnv "REPO_ROOT";
        intentPath = builtins.getEnv "INTENT_PATH";
        inventoryPath = builtins.getEnv "INVENTORY_PATH";

        cpmFlake = flake.inputs.network-control-plane-model;
        cpm = cpmFlake.lib.x86_64-linux.compileAndBuildFromPaths {
          inputPath = intentPath;
          inherit inventoryPath;
          validateForwardingModel = false;
          validateRuntimeModel = false;
        };

        hostBuild = flake.lib.renderer.buildHostFromControlPlane {
          controlPlaneOut = cpm;
          selector = "s-router-test";
          system = "x86_64-linux";
        };

        containers = hostBuild.renderedHost.containers or {};

        # Collect all routing policy rules across all containers
        getAllRules = cfg:
          let
            networks = cfg.systemd.network.networks or {};
          in
            builtins.concatLists
              (map (n: (networks.${n}.routingPolicyRules or []))
                (builtins.attrNames networks));

        pkgs = flake.inputs.nixpkgs.legacyPackages.x86_64-linux;
        allContainerRules = builtins.concatLists
          (map (name:
            let
              cont = containers.${name} or {};
              cfg = (lib.nixosSystem {
                system = "x86_64-linux";
                modules = [ (cont.config or {}) ];
              }).config;
            in getAllRules cfg
          ) (builtins.attrNames containers));

        # Check for prohibited catch-all rules:
        # To=0.0.0.0/0 or To=::/0 on shared interfaces
        catchAllRules = builtins.filter
          (r: (r.To or "") == "0.0.0.0/0" || (r.To or "") == "::/0")
          allContainerRules;

        noCatchAll = builtins.length catchAllRules == 0;
      in
        noCatchAll
        && builtins.trace "FS-370-HDS-010-SDS-010-SMS-120 P3: catch-all rules found: ${toString (builtins.length catchAllRules)}" true
    '

echo "PASS P3: No default-route catch-all rules on shared interfaces"

# ============================================================
# Predicate 4: Route entries point to correct DS-facing
# interface for each tenant subnet.
# ============================================================
echo ""
echo "--- Predicate 4: Route entries for tenant subnets ---"

nix_eval_true_or_fail "FS-370-HDS-010-SDS-010-SMS-120 P4: tenant subnet routes" \
  env REPO_ROOT="${repo_root}" \
    INTENT_PATH="${intent_path}" \
    INVENTORY_PATH="${inventory_path}" \
  nix eval \
    --extra-experimental-features 'nix-command flakes' \
    --impure --expr '
      let
        flake = builtins.getFlake ("path:" + builtins.getEnv "REPO_ROOT");
        lib = flake.inputs.nixpkgs.lib;
        repoRoot = builtins.getEnv "REPO_ROOT";
        intentPath = builtins.getEnv "INTENT_PATH";
        inventoryPath = builtins.getEnv "INVENTORY_PATH";

        cpmFlake = flake.inputs.network-control-plane-model;
        cpm = cpmFlake.lib.x86_64-linux.compileAndBuildFromPaths {
          inputPath = intentPath;
          inherit inventoryPath;
          validateForwardingModel = false;
          validateRuntimeModel = false;
        };

        hostBuild = flake.lib.renderer.buildHostFromControlPlane {
          controlPlaneOut = cpm;
          selector = "s-router-test";
          system = "x86_64-linux";
        };

        containers = hostBuild.renderedHost.containers or {};
        ds = containers."s-router-downstream-selector" or {};
        pkgs = flake.inputs.nixpkgs.legacyPackages.x86_64-linux;
        dsCfg = (lib.nixosSystem {
          system = "x86_64-linux";
          modules = [ (ds.config or {}) ];
        }).config;
        dsNetworks = dsCfg.systemd.network.networks or {};
        dsRoutes = builtins.concatLists
          (map (n: (dsNetworks.${n}.routes or []))
            (builtins.attrNames dsNetworks));

        # Should have routes for known tenant subnets through their lane peer.
        hasAdminRoute = builtins.any
          (r: (r.Destination or "") == "10.20.15.0/24" && (r.Gateway or "") == "10.10.0.0")
          dsRoutes;
        hasClientRoute = builtins.any
          (r: (r.Destination or "") == "10.20.20.0/24" && (r.Gateway or "") == "10.10.0.2")
          dsRoutes;

        # Routes should have a non-null Gateway (pointing to DS interface)
        tenantRoutes = builtins.filter
          (r: builtins.match "10.20.*" (r.Destination or "") != null) dsRoutes;
        allHaveGateway = builtins.all
          (r: (r.Gateway or null) != null) tenantRoutes;
      in
        hasAdminRoute
        && hasClientRoute
        && allHaveGateway
        && builtins.length tenantRoutes > 0
        && builtins.trace "FS-370-HDS-010-SDS-010-SMS-120 P4: ${toString (builtins.length tenantRoutes)} tenant routes, allHaveGateway=${builtins.toJSON allHaveGateway}" true
    '

echo "PASS P4: Route entries point to correct DS-facing lane gateways for tenant subnets"

# ============================================================
# Seeded Negative 1: Missing per-lane ip rule on policy DS
# ============================================================
echo ""
echo "--- Seeded Negative 1: Missing per-lane ip rule detection ---"

nix_eval_true_or_fail "FS-370-HDS-010-SDS-010-SMS-120 SN1: missing per-lane ip rule rejected" \
  env REPO_ROOT="${repo_root}" \
    INTENT_PATH="${intent_path}" \
    INVENTORY_PATH="${inventory_path}" \
  nix eval \
    --extra-experimental-features 'nix-command flakes' \
    --impure --expr '
      let
        flake = builtins.getFlake ("path:" + builtins.getEnv "REPO_ROOT");
        lib = flake.inputs.nixpkgs.lib;
        intentPath = builtins.getEnv "INTENT_PATH";
        inventoryPath = builtins.getEnv "INVENTORY_PATH";
        cpm = flake.inputs.network-control-plane-model.lib.x86_64-linux.compileAndBuildFromPaths {
          inputPath = intentPath;
          inherit inventoryPath;
          validateForwardingModel = false;
          validateRuntimeModel = false;
        };
        hostBuild = flake.lib.renderer.buildHostFromControlPlane {
          controlPlaneOut = cpm;
          selector = "s-router-test";
          system = "x86_64-linux";
        };
        ds = hostBuild.renderedHost.containers."s-router-downstream-selector" or {};
        dsCfg = (lib.nixosSystem {
          system = "x86_64-linux";
          modules = [ (ds.config or {}) ];
        }).config;
        dsNetworks = dsCfg.systemd.network.networks or {};
        dsRules = builtins.concatLists
          (map (n: (dsNetworks.${n}.routingPolicyRules or []))
            (builtins.attrNames dsNetworks));
        destinationRules = builtins.filter (r: builtins.hasAttr "To" r) dsRules;
        hasClientRule = rules:
          builtins.any (r: (r.To or "") == "10.20.20.0/24" && (r.IncomingInterface or "") == "policy-client") rules;
        missingClientRule =
          builtins.filter
            (r: !((r.To or "") == "10.20.20.0/24" && (r.IncomingInterface or "") == "policy-client"))
            destinationRules;
      in
        hasClientRule destinationRules
        && !(hasClientRule missingClientRule)
    '

echo "PASS SN1: Mutated artifact without client per-lane ip rule is rejected"

# ============================================================
# Seeded Negative 2: DS reverse forward rule absent
# ============================================================
echo ""
echo "--- Seeded Negative 2: DS reverse forward rule absence detection ---"

nix_eval_true_or_fail "FS-370-HDS-010-SDS-010-SMS-120 SN2: missing reverse nft rule rejected" \
  env REPO_ROOT="${repo_root}" \
    INTENT_PATH="${intent_path}" \
    INVENTORY_PATH="${inventory_path}" \
  nix eval \
    --extra-experimental-features 'nix-command flakes' \
    --impure --expr '
      let
        flake = builtins.getFlake ("path:" + builtins.getEnv "REPO_ROOT");
        lib = flake.inputs.nixpkgs.lib;
        intentPath = builtins.getEnv "INTENT_PATH";
        inventoryPath = builtins.getEnv "INVENTORY_PATH";
        cpm = flake.inputs.network-control-plane-model.lib.x86_64-linux.compileAndBuildFromPaths {
          inputPath = intentPath;
          inherit inventoryPath;
          validateForwardingModel = false;
          validateRuntimeModel = false;
        };
        hostBuild = flake.lib.renderer.buildHostFromControlPlane {
          controlPlaneOut = cpm;
          selector = "s-router-test";
          system = "x86_64-linux";
        };
        ds = hostBuild.renderedHost.containers."s-router-downstream-selector" or {};
        dsCfg = (lib.nixosSystem {
          system = "x86_64-linux";
          modules = [ (ds.config or {}) ];
        }).config;
        ruleset = dsCfg.networking.nftables.ruleset or "";
        reverseRule = "iifname \"policy-client\" oifname \"access-client\" accept comment \"selector-handoff-reverse--s-router-access-client--selector-to-policy-to-access-to-selector--fabric\"";
        hasReverse = value: lib.hasInfix reverseRule value;
        missingReverse = builtins.replaceStrings [ reverseRule ] [ "" ] ruleset;
      in
        hasReverse ruleset
        && !(hasReverse missingReverse)
    '

echo "PASS SN2: Mutated artifact without client reverse nft rule is rejected"

# ============================================================
# Seeded Negative 3: Default-route catch-all on shared interface
# ============================================================
echo ""
echo "--- Seeded Negative 3: Default-route catch-all prohibition ---"

nix_eval_true_or_fail "FS-370-HDS-010-SDS-010-SMS-120 SN3: default-route catch-all rejected" \
  env REPO_ROOT="${repo_root}" \
    INTENT_PATH="${intent_path}" \
    INVENTORY_PATH="${inventory_path}" \
  nix eval \
    --extra-experimental-features 'nix-command flakes' \
    --impure --expr '
      let
        flake = builtins.getFlake ("path:" + builtins.getEnv "REPO_ROOT");
        lib = flake.inputs.nixpkgs.lib;
        intentPath = builtins.getEnv "INTENT_PATH";
        inventoryPath = builtins.getEnv "INVENTORY_PATH";
        cpm = flake.inputs.network-control-plane-model.lib.x86_64-linux.compileAndBuildFromPaths {
          inputPath = intentPath;
          inherit inventoryPath;
          validateForwardingModel = false;
          validateRuntimeModel = false;
        };
        hostBuild = flake.lib.renderer.buildHostFromControlPlane {
          controlPlaneOut = cpm;
          selector = "s-router-test";
          system = "x86_64-linux";
        };
        containers = hostBuild.renderedHost.containers or {};
        getAllRules = container:
          let
            cfg = (lib.nixosSystem {
              system = "x86_64-linux";
              modules = [ (container.config or {}) ];
            }).config;
            networks = cfg.systemd.network.networks or {};
          in
            builtins.concatLists
              (map (n: (networks.${n}.routingPolicyRules or []))
                (builtins.attrNames networks));
        allContainerRules = builtins.concatLists
          (map (name: getAllRules containers.${name}) (builtins.attrNames containers));
        noCatchAll = rules:
          builtins.length
            (builtins.filter (r: (r.To or "") == "0.0.0.0/0" || (r.To or "") == "::/0") rules)
          == 0;
      in
        noCatchAll allContainerRules
        && !(noCatchAll (allContainerRules ++ [{ To = "0.0.0.0/0"; IncomingInterface = "policy-client"; }]))
    '

echo "PASS SN3: Mutated artifact with default-route catch-all is rejected"

# ============================================================
# Seeded Negative 4: Return-path route to wrong interface
# ============================================================
echo ""
echo "--- Seeded Negative 4: Wrong-interface route detection ---"

nix_eval_true_or_fail "FS-370-HDS-010-SDS-010-SMS-120 SN4: wrong lane gateway rejected" \
  env REPO_ROOT="${repo_root}" \
    INTENT_PATH="${intent_path}" \
    INVENTORY_PATH="${inventory_path}" \
  nix eval \
    --extra-experimental-features 'nix-command flakes' \
    --impure --expr '
      let
        flake = builtins.getFlake ("path:" + builtins.getEnv "REPO_ROOT");
        lib = flake.inputs.nixpkgs.lib;
        intentPath = builtins.getEnv "INTENT_PATH";
        inventoryPath = builtins.getEnv "INVENTORY_PATH";
        cpm = flake.inputs.network-control-plane-model.lib.x86_64-linux.compileAndBuildFromPaths {
          inputPath = intentPath;
          inherit inventoryPath;
          validateForwardingModel = false;
          validateRuntimeModel = false;
        };
        hostBuild = flake.lib.renderer.buildHostFromControlPlane {
          controlPlaneOut = cpm;
          selector = "s-router-test";
          system = "x86_64-linux";
        };
        ds = hostBuild.renderedHost.containers."s-router-downstream-selector" or {};
        dsCfg = (lib.nixosSystem {
          system = "x86_64-linux";
          modules = [ (ds.config or {}) ];
        }).config;
        dsNetworks = dsCfg.systemd.network.networks or {};
        dsRoutes = builtins.concatLists
          (map (n: (dsNetworks.${n}.routes or []))
            (builtins.attrNames dsNetworks));
        hasClientLaneGateway = routes:
          builtins.any (r: (r.Destination or "") == "10.20.20.0/24" && (r.Gateway or "") == "10.10.0.2") routes;
        wrongGatewayRoutes =
          map
            (r:
              if (r.Destination or "") == "10.20.20.0/24" then
                r // { Gateway = "10.10.0.4"; }
              else
                r)
            dsRoutes;
      in
        hasClientLaneGateway dsRoutes
        && !(hasClientLaneGateway wrongGatewayRoutes)
    '

echo "PASS SN4: Mutated artifact with wrong client lane gateway is rejected"

# ============================================================
# Predicate 5: Source code completeness check
# ============================================================
echo ""
echo "--- Predicate 5: Source code completeness ---"

# Verify the key implementation files exist
declare -A required_files=(
  ["policy-routing/rules.nix"]="ip rule generation"
  ["policy-routing/raw-routes.nix"]="route candidate assembly"
  ["policy-routing/return-routes.nix"]="tenant return destinations"
  ["policy-routing/forwarding-rules.nix"]="forwarding rule classification"
  ["policy-routing/aggregate.nix"]="policy table assembly"
  ["policy-routing/raw-routes/lane-match.nix"]="lane-interface matching"
)

all_files_present=true
for f in "${!required_files[@]}"; do
  file_path="${repo_root}/s88/ControlModule/render/container-networks/${f}"
  if [[ -f "${file_path}" ]]; then
    echo "  OK: ${f} (${required_files[$f]})"
  else
    echo "FAIL: ${f} missing (${required_files[$f]})"
    all_files_present=false
  fi
done

if ! ${all_files_present}; then
  all_checks_passed=false
fi

# ============================================================
# Report
# ============================================================
echo ""
if ${all_checks_passed}; then
  echo "PASS: FS-370-HDS-010-SDS-010-SMS-120 — NixOS renderer per-lane return-path routing predicates verified."
  echo "  - Per-lane ip rules with To=<tenant-subnet> on DS and policy nodes"
  echo "  - nftables forward chain with policy drop and per-lane accept rules/comments"
  echo "  - No default-route catch-all rules on shared interfaces"
  echo "  - Route entries point to correct DS-facing lane gateways"
  echo "  - 4 active seeded negatives verified by artifact mutation"
  exit 0
else
  echo "FAIL: FS-370-HDS-010-SDS-010-SMS-120 — one or more predicates failed."
  exit 1
fi
