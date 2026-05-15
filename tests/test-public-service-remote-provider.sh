#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"

# shellcheck source=tests/lib/test-common.sh
. "${repo_root}/tests/lib/test-common.sh"

nix_eval_true_or_fail "public-service-remote-provider" \
  nix eval --extra-experimental-features 'nix-command flakes' --impure --expr '
let
  flake = builtins.getFlake ("path:" + toString ./.);
  lib = flake.inputs.nixpkgs.lib;
  common = import ./s88/ControlModule/firewall/policy/core/common.nix { inherit lib; };
  catalog = import ./s88/ControlModule/firewall/policy/core/catalog.nix {
    inherit common;
    communicationContract = {
      trafficTypes = [
        {
          name = "public-test";
          match = [
            {
              family = "ipv4";
              proto = "tcp";
              dports = [ 4444 ];
            }
          ];
        }
      ];
      services = [
        {
          name = "remote-public";
          providers = [ "remote-client01" ];
          trafficType = "public-test";
        }
      ];
      relations = [
        {
          id = "allow-wan-to-remote-public";
          action = "allow";
          from = {
            kind = "external";
            name = "wan";
          };
          to = {
            kind = "service";
            name = "remote-public";
          };
          trafficType = "public-test";
        }
      ];
    };
    ownership = {
      endpoints = [ ];
    };
    inventory = {
      endpoints.remote-client01.ipv4 = [ "10.70.10.100" ];
    };
  };
  serviceNat = import ./s88/ControlModule/firewall/policy/core/service-nat.nix {
    inherit lib catalog common;
    interfaceSet = {
      wanNames = [ "wan0" ];
      wanEntries = [
        {
          name = "wan0";
          assignedUplinkName = "wan";
        }
      ];
    };
  };
in
  serviceNat.serviceNatEntries == [
    {
      relationName = "allow-wan-to-remote-public";
      serviceName = "remote-public";
      target = "10.70.10.100";
      ingressIfNames = [ "wan0" ];
      family = "ipv4";
      proto = "tcp";
      dport = 4444;
    }
  ]
'

echo "PASS public-service-remote-provider"
