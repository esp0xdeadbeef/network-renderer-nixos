#!/usr/bin/env bash
# GAMP-ID: FS-480-HDS-010-SDS-010-SMS-040
# GAMP-ID: FS-520-HDS-010-SDS-010-SMS-020
# GAMP-SCOPE: renderer-construction
set -euo pipefail

repo_root="${SMS_TEST_REPO_ROOT:-$(git -C "$(dirname "${BASH_SOURCE[0]}")" rev-parse --show-toplevel)}"
source "${repo_root}/tests/lib/test-common.sh"

run_negative_case() {
  local label="$1"
  local expected="$2"
  local expr="$3"
  local stderr_file
  stderr_file="$(mktemp)"

  set +e
  REPO_ROOT="${repo_root}" nix eval \
    --extra-experimental-features 'nix-command flakes' \
    --impure --json --expr "${expr}" \
    >/dev/null 2>"${stderr_file}"
  local rc=$?
  set -e

  [[ "${rc}" -ne 0 ]] || fail "FAIL bgp-runtime-contract-fail-closed:${label}: expected nix eval failure"
  grep -F "${expected}" "${stderr_file}" >/dev/null \
    || {
      cat "${stderr_file}" >&2
      fail "FAIL bgp-runtime-contract-fail-closed:${label}: missing expected diagnostic ${expected}"
    }

  rm -f "${stderr_file}"
}

run_negative_case \
  missing-asn \
  "runtimeTarget.bgp.asn must be an integer" \
  '
    let
      repoRoot = "path:" + builtins.getEnv "REPO_ROOT";
      flake = builtins.getFlake repoRoot;
      helper = import (flake.outPath + "/s88/ControlModule/render/containers/bgp-services.nix");
    in
    helper {
      lib = flake.inputs.nixpkgs.lib;
      renderedModel = {
        runtimeTarget = {
          routingMode = "bgp";
          bgp.neighbors = [
            {
              peer_addr4 = "192.0.2.2/31";
              peer_asn = 65020;
            }
          ];
        };
        interfaces.tenant-a = {
          sourceKind = "tenant";
          addr4 = "10.10.10.1/24";
          routes.ipv4 = [{ proto = "connected"; dst = "10.10.10.0/24"; }];
        };
      };
    }
  '

run_negative_case \
  missing-peer-asn \
  "runtimeTarget.bgp.neighbors[0].peer_asn must be an integer" \
  '
    let
      repoRoot = "path:" + builtins.getEnv "REPO_ROOT";
      flake = builtins.getFlake repoRoot;
      helper = import (flake.outPath + "/s88/ControlModule/render/containers/bgp-services.nix");
    in
    helper {
      lib = flake.inputs.nixpkgs.lib;
      renderedModel = {
        runtimeTarget = {
          routingMode = "bgp";
          bgp = {
            asn = 65010;
            neighbors = [
              {
                peer_addr4 = "192.0.2.2/31";
              }
            ];
          };
        };
        interfaces.tenant-a = {
          sourceKind = "tenant";
          addr4 = "10.10.10.1/24";
          routes.ipv4 = [{ proto = "connected"; dst = "10.10.10.0/24"; }];
        };
      };
    }
  '

run_negative_case \
  missing-peer-address \
  "runtimeTarget.bgp.neighbors[0] must carry peer_addr4 or peer_addr6" \
  '
    let
      repoRoot = "path:" + builtins.getEnv "REPO_ROOT";
      flake = builtins.getFlake repoRoot;
      helper = import (flake.outPath + "/s88/ControlModule/render/containers/bgp-services.nix");
    in
    helper {
      lib = flake.inputs.nixpkgs.lib;
      renderedModel = {
        runtimeTarget = {
          routingMode = "bgp";
          bgp = {
            asn = 65010;
            neighbors = [
              {
                peer_asn = 65020;
              }
            ];
          };
        };
        interfaces.tenant-a = {
          sourceKind = "tenant";
          addr4 = "10.10.10.1/24";
          routes.ipv4 = [{ proto = "connected"; dst = "10.10.10.0/24"; }];
        };
      };
    }
  '

pass "bgp-runtime-contract-fail-closed"
