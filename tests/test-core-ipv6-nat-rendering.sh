#!/usr/bin/env bash
# GAMP-ID: USR-INET-001-FS-001-HDS-001-SDS-001-001-SMS-001-005
# GAMP-ID: USR-INET-001-FS-001-HDS-001-SDS-001-001-SMS-001-CMC-001-005
# GAMP-ID: USR-MODEL-001-FS-001-HDS-001-SDS-001-002-SMS-001-003
# GAMP-ID: USR-MODEL-001-FS-001-HDS-001-SDS-001-002-SMS-001-CMC-001-003
# GAMP-ID: USR-MODEL-001-FS-001-HDS-002-SDS-001-001-SMS-001-009
# GAMP-ID: USR-MODEL-001-FS-001-HDS-002-SDS-001-001-SMS-001-010
# GAMP-ID: USR-MODEL-001-FS-001-HDS-002-SDS-001-001-SMS-001-CMC-001-009
# GAMP-ID: USR-MODEL-001-FS-001-HDS-002-SDS-001-001-SMS-001-CMC-001-010
set -euo pipefail
# LAB-SMT-ID: LAB-SMT-019
# LAB-SMT-SCOPE: examples-only; see network-labs/tests/SMT.md

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${repo_root}/tests/lib/test-common.sh"

example_root="$(flake_input_path network-labs)/examples/single-wan"
intent_path="${example_root}/intent.nix"
inventory_path="${example_root}/inventory-clab.nix"

result_json="$(mktemp)"
eval_stderr="$(mktemp)"
rules_file="$(mktemp)"
family_nat_json="$(mktemp)"
family_nat_stderr="$(mktemp)"
trap 'rm -f "${result_json}" "${eval_stderr}" "${rules_file}" "${family_nat_json}" "${family_nat_stderr}"' EXIT

nix_eval_json_or_fail \
  core-ipv6-nat-rendering \
  "${result_json}" \
  "${eval_stderr}" \
  env REPO_ROOT="${repo_root}" \
    INTENT_PATH="${intent_path}" \
    INVENTORY_PATH="${inventory_path}" \
    CPM_INPUT_PATH="${NETWORK_INPUT_PATH_NETWORK_CONTROL_PLANE_MODEL:-}" \
    nix eval \
    --extra-experimental-features 'nix-command flakes' \
    --impure --json --expr '
      let
        flake = builtins.getFlake ("path:" + builtins.getEnv "REPO_ROOT");
        lib = flake.inputs.nixpkgs.lib;
        system = "x86_64-linux";
        cpmInputPath = builtins.getEnv "CPM_INPUT_PATH";
        cpmInput =
          if cpmInputPath != "" then
            builtins.getFlake ("path:" + cpmInputPath)
          else
            flake.inputs.network-control-plane-model;
        rendererApi = import ./s88/Enterprise/default.nix {
          inherit lib;
          repoRoot = ./.;
          flakeInputs = flake.inputs // { network-control-plane-model = cpmInput; };
        };
        hostBuild = import (builtins.getEnv "REPO_ROOT" + "/tests/nix/build-host-from-paths.nix") {
          selector = "lab-host";
          inherit system;
        };
        builtContainers = import (builtins.getEnv "REPO_ROOT" + "/tests/nix/build-containers-from-paths.nix") {
          boxName = "lab-host";
          inherit system;
        };
        cfg = (lib.nixosSystem {
          inherit system;
          modules = [ builtContainers."s-router-core-wan".config ];
        }).config;
      in {
        rules = cfg.networking.nftables.ruleset;
        coreNatIntent =
          hostBuild.controlPlaneOut.control_plane_model.data.esp0xdeadbeef."site-a"
            .runtimeTargets."esp0xdeadbeef-site-a-s-router-core-wan".natIntent;
      }
    '

_jq -r '.rules' "${result_json}" >"${rules_file}"

if ! rg -q 'table ip nat' "${rules_file}" || ! rg -q 'oifname "eth0".*ip saddr .*masquerade' "${rules_file}"; then
  echo "FAIL core-ipv6-nat-rendering: expected source-scoped IPv4 NAT on rendered WAN eth0" >&2
  rg 'table ip|table ip6|postrouting|masquerade' "${rules_file}" >&2 || true
  exit 1
fi

nat6_expected="$(_jq -r '.coreNatIntent.families.ipv6 // false' "${result_json}")"
if [[ "${nat6_expected}" == "true" ]]; then
  if ! rg -q 'table ip6 nat' "${rules_file}" || ! rg -q 'oifname "eth0" masquerade' "${rules_file}"; then
    echo "FAIL core-ipv6-nat-rendering: expected IPv6 NAT on rendered WAN eth0 when CPM natIntent.families.ipv6 is true" >&2
    rg 'table ip|table ip6|postrouting|masquerade' "${rules_file}" >&2 || true
    exit 1
  fi
else
  if rg -q 'oifname "eth0" ip6 saddr .*masquerade|oifname "eth0" masquerade' "${rules_file}"; then
    echo "FAIL core-ipv6-nat-rendering: CPM disabled IPv6 NAT but renderer emitted WAN masquerade" >&2
    rg 'table ip|table ip6|postrouting|masquerade' "${rules_file}" >&2 || true
    exit 1
  fi
fi

scoped_rules="$(
  nix eval --raw --extra-experimental-features 'nix-command flakes' --impure --expr '
    let
      flake = builtins.getFlake ("path:" + toString ./.);
      renderRuleset = import ./s88/ControlModule/firewall/emission/render-ruleset.nix {
        lib = flake.inputs.nixpkgs.lib;
      };
    in
      renderRuleset {
        nat6Interfaces = [ "eth0" ];
        nat6SourcePrefixes = [ "fd42:dead:feed:10::/64" ];
      }
  '
)"

scoped_v4_rules="$(
  nix eval --raw --extra-experimental-features 'nix-command flakes' --impure --expr '
    let
      flake = builtins.getFlake ("path:" + toString ./.);
      renderRuleset = import ./s88/ControlModule/firewall/emission/render-ruleset.nix {
        lib = flake.inputs.nixpkgs.lib;
      };
    in
      renderRuleset {
        natInterfaces = [ "eth0" ];
        nat4SourcePrefixes = [ "10.20.10.0/24" ];
      }
  '
)"

if ! grep -Fq 'oifname "eth0" ip saddr 10.20.10.0/24 masquerade' <<<"${scoped_v4_rules}"; then
  echo "FAIL core-ipv6-nat-rendering: explicit IPv4 NAT source prefixes must scope NAT44" >&2
  printf "%s\n" "${scoped_v4_rules}" >&2
  exit 1
fi

if grep -Fq 'oifname "eth0" masquerade' <<<"${scoped_v4_rules}"; then
  echo "FAIL core-ipv6-nat-rendering: source-scoped NAT44 must not also emit unscoped masquerade" >&2
  printf "%s\n" "${scoped_v4_rules}" >&2
  exit 1
fi

if ! grep -Fq 'oifname "eth0" ip6 saddr fd42:dead:feed:10::/64 masquerade' <<<"${scoped_rules}"; then
  echo "FAIL core-ipv6-nat-rendering: explicit IPv6 NAT source prefixes must scope NAT66" >&2
  printf "%s\n" "${scoped_rules}" >&2
  exit 1
fi

if grep -Fq 'oifname "eth0" masquerade' <<<"${scoped_rules}"; then
  echo "FAIL core-ipv6-nat-rendering: source-scoped NAT66 must not also emit unscoped masquerade" >&2
  rg 'table ip|table ip6|postrouting|masquerade' "${rules_file}" >&2 || true
  exit 1
fi

nix_eval_json_or_fail \
  core-ipv6-nat-rendering \
  "${family_nat_json}" \
  "${family_nat_stderr}" \
  env REPO_ROOT="${repo_root}" \
    nix eval \
    --extra-experimental-features 'nix-command flakes' \
    --impure --json --expr '
      let
        repoRoot = builtins.getEnv "REPO_ROOT";
        flake = builtins.getFlake ("path:" + repoRoot);
        lib = flake.inputs.nixpkgs.lib;
        forwardingIntent = import (repoRoot + "/s88/ControlModule/firewall/lookup/forwarding-intent.nix") {
          inherit lib;
          runtimeTarget = {
            natIntent = {
              enabled = true;
              families = {
                ipv4 = false;
                ipv6 = true;
              };
              masqueradeInterfaces6 = [ "isp-a" ];
              masqueradeSourcePrefixes6 = [ "fd42:dead:beef:20::/64" ];
            };
          };
          interfaces = {
            isp-a = {
              name = "isp-a";
              sourceKind = "wan";
            };
            tenant-client = {
              name = "tenant-client";
              sourceKind = "tenant";
            };
          };
          wanIfs = [ "isp-a" ];
          lanIfs = [ "tenant-client" ];
          uplinks = { };
        };
        coreForwarding = import (repoRoot + "/s88/ControlModule/firewall/policy/core/forwarding.nix") {
          inherit lib forwardingIntent;
          uplinks = { };
          wanNames = [ "isp-a" ];
          lanNames = [ "tenant-client" ];
          forwardEgressNames = [ "isp-a" ];
          overlayIngressNames = [ ];
          adapterNames = [ "tenant-client" ];
        };
        renderRuleset = import (repoRoot + "/s88/ControlModule/firewall/emission/render-ruleset.nix") {
          inherit lib;
        };
      in {
        authoritativeCoreNat = forwardingIntent.authoritativeCoreNat;
        nat6Interfaces = coreForwarding.nat6Interfaces;
        nat6SourcePrefixes = coreForwarding.nat6SourcePrefixes;
        rules = renderRuleset {
          nat6Interfaces = coreForwarding.nat6Interfaces;
          nat6SourcePrefixes = coreForwarding.nat6SourcePrefixes;
        };
      }
    '

if [[ "$(_jq -r '.authoritativeCoreNat' "${family_nat_json}")" != "true" ]]; then
  echo "FAIL core-ipv6-nat-rendering: family-specific NAT66 interfaces must mark core NAT intent authoritative" >&2
  _jq '.' "${family_nat_json}" >&2
  exit 1
fi

if [[ "$(_jq -r '.nat6Interfaces | join(",")' "${family_nat_json}")" != "isp-a" ]]; then
  echo "FAIL core-ipv6-nat-rendering: family-specific NAT66 interfaces must flow into core firewall forwarding" >&2
  _jq '.' "${family_nat_json}" >&2
  exit 1
fi

if ! _jq -r '.rules' "${family_nat_json}" | grep -Fq 'oifname "isp-a" ip6 saddr fd42:dead:beef:20::/64 masquerade'; then
  echo "FAIL core-ipv6-nat-rendering: family-specific NAT66 intent must render source-scoped IPv6 masquerade" >&2
  _jq -r '.rules' "${family_nat_json}" >&2
  exit 1
fi

pass "core-ipv6-nat-rendering"
