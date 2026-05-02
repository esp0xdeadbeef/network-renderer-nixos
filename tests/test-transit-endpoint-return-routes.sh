#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

source "${repo_root}/tests/lib/test-common.sh"

search_root="$(flake_input_path network-labs)/examples"
example_root="${search_root}/dual-wan-branch-overlay-bgp"
intent_path="${example_root}/intent.nix"
inventory_path="${example_root}/inventory-nixos.nix"

[[ -f "${intent_path}" ]] || fail "missing intent fixture: ${intent_path}"
[[ -f "${inventory_path}" ]] || fail "missing inventory fixture: ${inventory_path}"

REPO_ROOT="${repo_root}" \
INTENT_PATH="${intent_path}" \
INVENTORY_PATH="${inventory_path}" \
  nix eval \
    --extra-experimental-features 'nix-command flakes' \
    --impure --expr '
      let
        flake = builtins.getFlake ("path:" + builtins.getEnv "REPO_ROOT");
        host = flake.lib.renderer.buildHostFromPaths {
          selector = "lab-host";
          system = "x86_64-linux";
          intentPath = builtins.getEnv "INTENT_PATH";
          inventoryPath = builtins.getEnv "INVENTORY_PATH";
        };
        rendered = host.renderedHost.containers."s-router-core-isp-a";
        cfg =
          (flake.inputs.nixpkgs.lib.nixosSystem {
            system = "x86_64-linux";
            modules = [ rendered.config ];
          }).config;
        routes = cfg.systemd.network.networks."10-ens3".routes or [ ];
        hasRoute = destination: gateway:
          builtins.any
            (route:
              (route.Destination or null) == destination
              && (route.Gateway or null) == gateway)
            routes;
      in
        hasRoute "10.19.0.8/32" "10.10.0.9"
        && hasRoute "fd42:dead:beef:1900:0000:0000:0000:0008/128" "fd42:dead:beef:1000:0:0:0:9"
    ' | grep -qx true

REPO_ROOT="${repo_root}" \
INTENT_PATH="$(flake_input_path network-labs)/examples/s-router-test-three-site/intent.nix" \
INVENTORY_PATH="$(flake_input_path network-labs)/examples/s-router-test-three-site/inventory-nixos.nix" \
  nix eval \
    --extra-experimental-features 'nix-command flakes' \
    --impure --expr '
      let
        flake = builtins.getFlake ("path:" + builtins.getEnv "REPO_ROOT");
        host = flake.lib.renderer.buildHostFromPaths {
          selector = "s-router-test";
          system = "x86_64-linux";
          intentPath = builtins.getEnv "INTENT_PATH";
          inventoryPath = builtins.getEnv "INVENTORY_PATH";
        };
        renderedUpstream = host.renderedHost.containers."c-router-upstream-selector";
        renderedBranchCore = host.renderedHost.containers."s-router-core-isp-b";
        cfgUpstream =
          (flake.inputs.nixpkgs.lib.nixosSystem {
            system = "x86_64-linux";
            modules = [ renderedUpstream.config ];
          }).config;
        cfgBranchCore =
          (flake.inputs.nixpkgs.lib.nixosSystem {
            system = "x86_64-linux";
            modules = [ renderedBranchCore.config ];
          }).config;
        iotRoutes = cfgUpstream.systemd.network.networks."10-policy-iot-wan".routes or [ ];
        mgmtStorageRoutes = cfgUpstream.systemd.network.networks."10-pol-mgt-sto".routes or [ ];
        mgmtRoutes = cfgUpstream.systemd.network.networks."10-policy-mgmt-wan".routes or [ ];
        renderedPolicy = host.renderedHost.containers."c-router-policy";
        cfgPolicy =
          (flake.inputs.nixpkgs.lib.nixosSystem {
            system = "x86_64-linux";
            modules = [ renderedPolicy.config ];
          }).config;
        policyNases = cfgPolicy.systemd.network.networks."10-up-nas-storage".routes or [ ];
        policyPrinter = cfgPolicy.systemd.network.networks."10-up-prn-sto".routes or [ ];
        nasRules = cfgPolicy.systemd.network.networks."10-downstream-nas".routingPolicyRules or [ ];
        printerRules = cfgPolicy.systemd.network.networks."10-down-printer".routingPolicyRules or [ ];
        branchCoreNetworks = cfgBranchCore.systemd.network.networks;
        hasRoute = routes: destination: gateway:
          builtins.any
            (route:
              (route.Destination or null) == destination
              && (route.Gateway or null) == gateway
              && (route.Table or null) == 2000)
            routes;
        hasTableRoute = table: routes: destination: gateway:
          builtins.any
            (route:
              (route.Destination or null) == destination
              && (route.Gateway or null) == gateway
              && (route.Table or null) == table)
            routes;
        hasPolicyRule = table: ingress: rules:
          builtins.any
            (rule:
              (rule.IncomingInterface or null) == ingress
              && (rule.Table or null) == table)
            rules;
        hasMainRoute = routes: destination: gateway:
          builtins.any
            (route:
              (route.Destination or null) == destination
              && (route.Gateway or null) == gateway
              && !(builtins.hasAttr "Table" route))
            routes;
        hasMainRouteAnyNetwork = networks: destination: gateway:
          builtins.any
            (networkName: hasMainRoute (networks.${networkName}.routes or [ ]) destination gateway)
            (builtins.attrNames networks);
      in
        (!hasRoute iotRoutes "10.80.0.4/31" "10.80.0.22")
        && (!hasRoute mgmtStorageRoutes "10.80.0.4/31" "10.80.0.26")
        && hasRoute mgmtRoutes "10.80.0.4/31" "10.80.0.30"
        && hasTableRoute 2003 policyNases "10.20.10.0/24" "10.80.0.33"
        && hasTableRoute 2003 policyNases "fd42:dead:beef:0010:0000:0000:0000:0000/64" "fd42:dead:cafe:1000:0:0:0:21"
        && hasTableRoute 2004 policyPrinter "10.20.10.0/24" "10.80.0.37"
        && hasTableRoute 2004 policyPrinter "fd42:dead:beef:0010:0000:0000:0000:0000/64" "fd42:dead:cafe:1000:0:0:0:25"
        && hasPolicyRule 2003 "downstream-nas" nasRules
        && hasPolicyRule 2004 "down-printer" printerRules
        && hasMainRouteAnyNetwork branchCoreNetworks "10.50.0.0/32" "10.10.0.13"
        && hasMainRouteAnyNetwork branchCoreNetworks "fd42:dead:beef:1000:0:0:0:0/128" "fd42:dead:beef:1000:0:0:0:d"
    ' | grep -qx true

echo "PASS transit-endpoint-return-routes"
