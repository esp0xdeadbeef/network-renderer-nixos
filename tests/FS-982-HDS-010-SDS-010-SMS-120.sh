#!/usr/bin/env bash
# GAMP-ID: FS-982-HDS-010-SDS-010-SMS-120
# GAMP-SCOPE: software-module-test
set -euo pipefail

repo_root="${NETWORK_RENDERER_NIXOS_ROOT:-$(git -C "$(dirname "${BASH_SOURCE[0]}")" rev-parse --show-toplevel)}"

REPO_ROOT="${repo_root}" nix eval --impure --raw --expr '
  let
    repoRoot = builtins.getEnv "REPO_ROOT";
    flake = builtins.getFlake ("path:" + repoRoot);
    lib = flake.inputs.nixpkgs.lib;
    # CANONICAL INPUT ONLY (RR_RAW_CPM_INPUT, FS-310-HDS-040-SDS-010-SMS-100): the module
    # maps the validated bundle '"'"'s `canonicalSites`, never the producer model. The fixture
    # therefore builds the site tree it wants and hands it over as canonical content.
    render = data: hostName: renderedNetworks:
      import (repoRoot + "/s88/ControlModule/render/host-management.nix") {
        inherit lib hostName renderedNetworks;
        cpm = { };
        canonicalCollections = { canonicalSites = { byEnterprise = data; }; };
      };
    runtimeTarget = deploymentHost: logicalInterface: linkName: {
      kind = "host-management-runtime-target";
      schemaVersion = 1;
      inherit deploymentHost logicalInterface;
      purpose = "hardware-management";
      managementOnly = true;
      link = { kind = "bridge"; name = linkName; };
      addressAcquisition = {
        ipv4 = "dhcp";
        ipv6 = "disabled";
        acceptRA = false;
        useDns = false;
        defaultRoute = false;
      };
    };
    completeSite.hostManagement = {
      validated = true;
      diagnostics = [ ];
      requirement = {
        required = true;
        logicalInterface = "logical-management-a";
        purpose = "hardware-management";
        managementOnly = true;
      };
      runtimeTarget = runtimeTarget "fixture-host" "logical-management-a" "fixture-platform-link";
    };
    complete = render { fixture = { fixture-site = completeSite; }; } "fixture-host" {
      "30-fixture-platform-link" = {
        matchConfig.Name = "fixture-platform-link";
        networkConfig.DHCP = "no";
      };
    };
    renamedSite.hostManagement = completeSite.hostManagement // {
      runtimeTarget = runtimeTarget "renamed-host" "renamed-logical-surface" "renamed-platform-link";
    };
    renamed = render { fixture = { fixture-site = renamedSite; }; } "renamed-host" { };
    missingSite.hostManagement = {
      validated = false;
      runtimeTarget = null;
      requirement.required = true;
      diagnostics = [ {
        code = "HOST_MANAGEMENT_BINDING_MISSING";
        severity = "warning";
        sourceLayer = "inventory";
        traceId = "FS-982-HDS-010-SDS-010-SMS-120";
        message = "Required host management has no explicit deployment-host binding";
      } ];
    };
    missing = render { fixture = { fixture-site = missingSite; }; } "fixture-host" { };
    duplicate = render { fixture = { fixture-site = completeSite; }; } "fixture-host" {
      first.matchConfig.Name = "fixture-platform-link";
      second.matchConfig.Name = "fixture-platform-link";
    };
    require = condition: message: if condition then true else throw message;
  in
    if
      require complete.handled "renderer did not claim the canonical host-management contract"
      && require complete.manageDhcp "renderer did not materialize DHCPv4"
      && require (builtins.attrNames complete.networks == [ "30-fixture-platform-link" ])
        "renderer created a parallel network unit instead of merging the explicit link owner"
      && require (complete.networks."30-fixture-platform-link".networkConfig.DHCP == "ipv4")
        "renderer did not enable DHCPv4 on the bound link"
      && require (complete.networks."30-fixture-platform-link".dhcpV4Config.UseDNS == false)
        "renderer allowed management DHCP to replace DNS"
      && require (complete.networks."30-fixture-platform-link".dhcpV4Config.UseRoutes == false)
        "renderer allowed management DHCP to install default routes"
      && require (renamed.networks."50-renamed-platform-link".matchConfig.Name == "renamed-platform-link")
        "renderer inferred a VLAN/interface label instead of using the explicit renamed link"
      && require (missing.networks == { } && builtins.length missing.warnings == 1)
        "missing inventory binding did not warn and suppress partial output"
      && require (lib.hasInfix "HOST_MANAGEMENT_BINDING_MISSING" (builtins.head missing.warnings))
        "missing-binding warning lost its deterministic code"
      && require (duplicate.networks == { } && builtins.length duplicate.warnings == 1)
        "duplicate link ownership did not warn and fail closed"
    then "ok" else throw "unreachable"
' >/dev/null

echo "PASS FS-982-HDS-010-SDS-010-SMS-120 renderer native host-management materialization"
