#!/usr/bin/env bash
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
      normalizedInterfacesForUnit = _: {
        wan = {
          sourceKind = "wan";
          usePrimaryHostBridge = true;
          renderedHostBridgeName = "br-wan";
          assignedUplinkName = "wan";
          containerInterfaceName = "eth0";
          addresses = [ "172.31.254.3/24" ];
          routes = [
            {
              dst = "0.0.0.0/0";
              via4 = "172.31.254.1";
            }
          ];
        };
      };
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
    };
    wanUplinkName = "wan";
  };
  eth0 = network.networks."10-eth0";
  checks = {
    explicitWanSkipsNetworkManager = containerModel.networkManagerWanInterfaces == [ ];
    explicitWanKeepsStaticAddress = eth0.address == [ "172.31.254.3/24" ];
    explicitWanDisablesDhcp = !(eth0.networkConfig ? DHCP) || eth0.networkConfig.DHCP == "no";
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
