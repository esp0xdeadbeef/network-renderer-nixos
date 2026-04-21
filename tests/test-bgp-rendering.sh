#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${repo_root}/tests/lib/test-common.sh"

labs_root="$(flake_input_path network-labs)"
example_dir="${labs_root}/examples/single-wan-uplink-ebgp"
intent_path="${example_dir}/intent.nix"
inventory_path="${example_dir}/inventory-nixos.nix"

[[ -f "${intent_path}" ]] || fail "missing intent.nix: ${intent_path}"
[[ -f "${inventory_path}" ]] || fail "missing inventory-nixos.nix: ${inventory_path}"

eval_container_frr() {
  local container_name="$1"

  REPO_ROOT="${repo_root}" \
  INTENT_PATH="${intent_path}" \
  INVENTORY_PATH="${inventory_path}" \
  CONTAINER_NAME="${container_name}" \
    nix eval \
      --extra-experimental-features 'nix-command flakes' \
      --impure --json --expr '
        let
          repoRoot = "path:" + builtins.getEnv "REPO_ROOT";
          intentPath = builtins.getEnv "INTENT_PATH";
          inventoryPath = builtins.getEnv "INVENTORY_PATH";
          containerName = builtins.getEnv "CONTAINER_NAME";
          flake = builtins.getFlake repoRoot;
          system = "x86_64-linux";
          hostBuild = flake.lib.renderer.buildHostFromPaths {
            selector = "lab-host";
            inherit system intentPath inventoryPath;
          };
          container = hostBuild.renderedHost.containers.${containerName};
          evaluated = flake.inputs.nixpkgs.lib.nixosSystem {
            inherit system;
            modules = [ container.config ];
          };
        in
        {
          bgpdEnable = evaluated.config.services.frr.bgpd.enable or false;
          config = evaluated.config.services.frr.config or "";
        }
      '
}

core_json="$(eval_container_frr "s-router-core-wan")"
policy_json="$(eval_container_frr "s-router-policy")"
access_json="$(eval_container_frr "s-router-access-mgmt")"

printf '%s' "${core_json}" | _jq -e '.bgpdEnable == true' >/dev/null
printf '%s' "${policy_json}" | _jq -e '.bgpdEnable == true' >/dev/null
printf '%s' "${access_json}" | _jq -e '.bgpdEnable == true' >/dev/null

printf '%s' "${core_json}" | _jq -e '.config | contains("router bgp 65000")' >/dev/null
printf '%s' "${core_json}" | _jq -e '.config | contains("neighbor 203.0.113.1 remote-as 64512")' >/dev/null
printf '%s' "${core_json}" | _jq -e '.config | contains("neighbor 10.19.0.5 remote-as 65000")' >/dev/null
printf '%s' "${policy_json}" | _jq -e '.config | contains("route-reflector-client")' >/dev/null
printf '%s' "${access_json}" | _jq -e '.config | contains("network 10.20.10.0/24")' >/dev/null
printf '%s' "${access_json}" | _jq -e '.config | contains("network fd42:dead:beef:0010:0000:0000:0000:0000/64")' >/dev/null

pass "bgp-rendering:single-wan-uplink-ebgp"
