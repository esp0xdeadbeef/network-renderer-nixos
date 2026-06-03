#!/usr/bin/env bash
# GAMP-ID: USR-MODEL-001-FS-001-HDS-002-SDS-001-001-SMS-001-001
# GAMP-ID: USR-MODEL-001-FS-001-HDS-002-SDS-001-001-SMS-001-004
# GAMP-ID: USR-MODEL-001-FS-001-HDS-002-SDS-001-001-SMS-001-006
# GAMP-ID: USR-MODEL-001-FS-001-HDS-002-SDS-001-001-SMS-001-CMC-001-001
# GAMP-ID: USR-MODEL-001-FS-001-HDS-002-SDS-001-001-SMS-001-CMC-001-004
# GAMP-ID: USR-MODEL-001-FS-001-HDS-002-SDS-001-001-SMS-001-CMC-001-006
# GAMP-SCOPE: software-module-test
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"

# shellcheck source=tests/lib/test-common.sh
. "${repo_root}/tests/lib/test-common.sh"

result_json="$(mktemp)"
stderr_file="$(mktemp)"
trap 'rm -f "$result_json" "$stderr_file"' EXIT

nix_eval_json_or_fail "static-host-bridge-wan" "$result_json" "$stderr_file" \
  nix eval --json --extra-experimental-features 'nix-command flakes' --impure \
  --expr '
let
  flake = builtins.getFlake ("path:" + toString ./.);
  lib = flake.inputs.nixpkgs.lib;
  normalizedWanInterfaces =
    (import ./s88/ControlModule/mapping/container-runtime/interfaces.nix {
      inherit lib;
      lookup = {
        sortedAttrNames = attrs: builtins.sort builtins.lessThan (builtins.attrNames attrs);
        bridgeNameMap = { };
        localAttachTargets = [
          {
            unitName = "c-router-core";
            ifName = "wan";
            renderedHostBridgeName = "br-wan";
            assignedUplinkName = "wan";
            identity.portName = "wan";
          }
        ];
      };
    }).normalizedInterfacesForUnit {
      unitName = "c-router-core";
      containerName = "c-router-core";
      interfaces.wan = {
        sourceKind = "wan";
        hostBridge = "br-wan";
        ipv4.address = "172.31.254.3/24";
        ipv6.address = "2001:db8:113::2/64";
        routes = [
          {
            dst = "0.0.0.0/0";
            via4 = "172.31.254.1";
          }
          {
            dst = "::/0";
            proto = "upstream";
          }
        ];
      };
    };
  assembly = import ./s88/ControlModule/mapping/container-runtime/model/container-assembly.nix {
    inherit lib;
    lookup = {
      runtimeTargetForUnit = _: {
        logicalNode = { };
        interfaces = { };
      };
      sortedAttrNames = attrs: builtins.sort builtins.lessThan (builtins.attrNames attrs);
      roleForUnit = _: "core";
      roleConfigForUnit = _: { };
      containerConfigForUnit = _: { };
      deploymentHostName = "hetzner";
      siteData = { };
      inventorySiteData = { };
      hostContext = { };
    };
    naming = {
      emittedUnitNameForUnit = name: name;
      containerNameForUnit = name: name;
    };
    interfaces = {
      normalizedInterfacesForUnit = _: normalizedWanInterfaces;
      vethsForInterfaces = _: { };
    };
  };
  containerModel = assembly.mkContainerRuntime "c-router-core";
  network = import ./s88/ControlModule/render/container-networks.nix {
    inherit lib containerModel;
    uplinks.wan = {
      bridge = "br-wan";
      ipv4 = {
        enable = true;
        dhcp = true;
      };
      ipv6 = {
        enable = true;
        acceptRA = false;
      };
    };
    wanUplinkName = "wan";
  };
  eth0 = network.networks."10-eth0";
  checks = {
    explicitWanSkipsNetworkManager = containerModel.networkManagerWanInterfaces == [ ];
    explicitWanKeepsStaticAddress = eth0.address == [ "172.31.254.3/24" "2001:db8:113::2/64" ];
    nestedUplinkAddressNormalized = normalizedWanInterfaces.wan.addresses == [ "172.31.254.3/24" "2001:db8:113::2/64" ];
    explicitWanDisablesDhcp = !(eth0.networkConfig ? DHCP) || eth0.networkConfig.DHCP == "no";
    explicitWanDoesNotForceIpv6RA = (eth0.networkConfig.IPv6AcceptRA or false) == false;
    explicitWanDisablesLinkLocalWithoutRA = (eth0.networkConfig.LinkLocalAddressing or null) == "no";
    explicitWanDoesNotRequestAcceptRASysctl = network.ipv6AcceptRAInterfaces == [ ];
    explicitWanKeepsDefaultRoute = builtins.elem {
      Destination = "0.0.0.0/0";
      Gateway = "172.31.254.1";
      GatewayOnLink = true;
    } eth0.routes;
  };
in
{
  ok = builtins.all (value: value == true) (builtins.attrValues checks);
  failed = lib.mapAttrsToList (name: _value: name) (lib.filterAttrs (_name: value: value != true) checks);
  inherit checks;
}
'

assert_json_checks_ok "static-host-bridge-wan" "$result_json"
echo "PASS static-host-bridge-wan"
