#!/usr/bin/env bash
# GAMP-ID: FS-380-HDS-020-SDS-010-SMS-050-CMC-001
# Verifies that policy endpoint mapping preserves multiple access-uplink lanes
# when a transit node resolves a tenant endpoint through parallel uplink lanes.
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

actual="$(
  REPO_ROOT="${repo_root}" nix eval \
    --extra-experimental-features 'nix-command flakes' \
    --impure --json --expr '
      let
        repoRoot = builtins.getEnv "REPO_ROOT";
        flake = builtins.getFlake ("path:" + repoRoot);
        lib = flake.inputs.nixpkgs.lib;
        endpointMap = import (repoRoot + "/s88/ControlModule/firewall/mapping/policy-endpoints.nix") {
          inherit lib;
          currentSite = {
            attachments = [
              {
                kind = "tenant";
                name = "client";
                unit = "client-edge";
              }
            ];
            transit.adjacencies = [
              {
                link = "p2p-policy-upstream-selector--access-client-edge--uplink-internet-vlan4";
                endpoints = [
                  { unit = "policy"; }
                  { unit = "upstream-selector"; }
                ];
                laneMeta = {
                  kind = "access-uplink";
                  access = "client-edge";
                  uplink = "internet-vlan4";
                  uplinks = [ "internet-vlan4" ];
                };
              }
              {
                link = "p2p-policy-upstream-selector--access-client-edge--uplink-internet-vlan5";
                endpoints = [
                  { unit = "policy"; }
                  { unit = "upstream-selector"; }
                ];
                laneMeta = {
                  kind = "access-uplink";
                  access = "client-edge";
                  uplink = "internet-vlan5";
                  uplinks = [ "internet-vlan5" ];
                };
              }
              {
                link = "p2p-downstream-selector-policy--access-client-edge";
                endpoints = [
                  { unit = "downstream-selector"; }
                  { unit = "policy"; }
                ];
                laneMeta = {
                  kind = "access";
                  access = "client-edge";
                };
              }
              {
                link = "p2p-client-edge-downstream-selector";
                endpoints = [
                  { unit = "client-edge"; }
                  { unit = "downstream-selector"; }
                ];
                laneMeta = {
                  kind = "access-edge";
                  access = "client-edge";
                };
              }
            ];
          };
          runtimeTarget.interfaces = {
            p4.logicalNode = "upstream-selector";
            p5.logicalNode = "upstream-selector";
          };
          interfaceView.interfaceEntries = [
            {
              name = "p4";
              logicalNode = "upstream-selector";
              sourceKind = "p2p";
              backingRef = {
                name = "p2p-policy-upstream-selector--access-client-edge--uplink-internet-vlan4";
                lane = {
                  kind = "access-uplink";
                  access = "client-edge";
                  uplink = "internet-vlan4";
                  uplinks = [ "internet-vlan4" ];
                };
              };
            }
            {
              name = "p5";
              logicalNode = "upstream-selector";
              sourceKind = "p2p";
              backingRef = {
                name = "p2p-policy-upstream-selector--access-client-edge--uplink-internet-vlan5";
                lane = {
                  kind = "access-uplink";
                  access = "client-edge";
                  uplink = "internet-vlan5";
                  uplinks = [ "internet-vlan5" ];
                };
              };
            }
          ];
        };
      in
        endpointMap.resolveEndpoint {
          kind = "tenant";
          name = "client";
        }
    '
)"

expected='["p4","p5"]'
if [[ "${actual}" != "${expected}" ]]; then
  printf 'FAIL: expected multi-lane tenant endpoint %s, got %s\n' "${expected}" "${actual}" >&2
  exit 1
fi

printf 'PASS: multi-lane tenant endpoint resolves both access-uplink interfaces\n'
