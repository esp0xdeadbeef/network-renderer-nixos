#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${repo_root}/tests/lib/test-common.sh"

examples_root="${1:-$(flake_input_path network-labs)/examples}"
examples_root="$(realpath "${examples_root}")"

labels=(
  single-wan
  single-wan-any-to-any-fw
  single-wan-bgp
  single-wan-direct-transit
  single-wan-ipv6-pd
  single-wan-uplink-ebgp
  single-wan-uplink-static-egress
  single-wan-vlan-trunk-lanes
  single-wan-with-nebula
  single-wan-with-nebula-any-to-any-fw
  multi-wan
  multi-wan-dedicated-lanes
  multi-enterprise
  overlay-east-west
  priority-stability
  ipv6-pd-downstream-delegation
  dual-wan-branch-overlay
  dual-wan-branch-overlay-bgp
  s-router-overlay-dns-lane-policy
  s-router-public-overlay-service
  tri-site-dual-wan-overlay-integration-static
  tri-site-dual-wan-overlay-integration-bgp
)

default_jobs="$(nproc 2>/dev/null || getconf _NPROCESSORS_ONLN 2>/dev/null || printf '8')"
test_jobs="${TEST_JOBS:-${default_jobs}}"
if ! [[ "${test_jobs}" =~ ^[0-9]+$ ]] || (( test_jobs < 1 )); then
  fail "TEST_JOBS must be a positive integer, got: ${test_jobs}"
fi

render_example() {
  local label="$1"
  local out_dir="$2"
  local case_dir="${examples_root}/${label}"
  local intent_path="${case_dir}/intent.nix"
  local inventory_path="${case_dir}/inventory-nixos.nix"

  [[ -f "${intent_path}" ]] || fail "missing intent.nix for ${label}: ${intent_path}"
  [[ -f "${inventory_path}" ]] || fail "missing inventory-nixos.nix for ${label}: ${inventory_path}"

  build_cpm_json "${intent_path}" "${inventory_path}" "${out_dir}/cpm.json"

  REPO_ROOT="${repo_root}" \
  CPM_PATH="${out_dir}/cpm.json" \
  INVENTORY_PATH="${inventory_path}" \
    nix eval \
      --extra-experimental-features 'nix-command flakes' \
      --impure --json \
      --expr '
        let
          flake = builtins.getFlake ("path:" + builtins.getEnv "REPO_ROOT");
        in
          flake.lib.renderer.renderDryConfig {
            cpmPath = builtins.getEnv "CPM_PATH";
            inventoryPath = builtins.getEnv "INVENTORY_PATH";
            exampleDir = builtins.dirOf (builtins.getEnv "CPM_PATH");
            debug = true;
          }
      ' > "${out_dir}/dry.json"
}

assert_safe_defaults() {
  local label="$1"
  local dry_json="$2"
  local cpm_json="$3"
  local result_json
  result_json="$(mktemp)"

  _jq --arg label "${label}" --slurpfile cpm "${cpm_json}" '
    def explicit_overlay_interfaces($hostName; $containerName):
      [
        $cpm[0].control_plane_model.data
        | to_entries[]
        | .value
        | to_entries[]
        | (.value.runtimeTargets // {})
        | to_entries[]
        | select((.value.placement.host // "") == $hostName)
        | select((.value.logicalNode.name // "") == $containerName)
        | (.value.effectiveRuntimeRealization.interfaces // {})
        | to_entries[]
        | select((.value.sourceKind // "") == "overlay")
        | (.value.renderedIfName // .value.containerInterfaceName // .value.name // .key)
        | select(type == "string" and length > 0)
      ]
      | unique;
    def containers:
      (.render.containers // {})
      | to_entries[] as $host
      | $host.value
      | to_entries[]
      | {
          label: $label,
          host: $host.key,
          name: .key,
          role: (.value.specialArgs.s88RoleName // ""),
          rules: (.value.firewall.ruleset // ""),
          explicitOverlayInterfaces: explicit_overlay_interfaces($host.key; .key)
        };
    def has($s): .rules | contains($s);
    def is_router: (.rules | length) > 0;
    def is_overlay_core:
      .role == "core" and (.rules | contains("allow-overlay-to-core"));
    def quoted_interface_names:
      [ .rules | scan("(?:iifname|oifname) \"([^\"]+)\"") | .[0] ] | unique;
    def unexpected_provider_interfaces:
      .explicitOverlayInterfaces as $explicitOverlayInterfaces
      |
      quoted_interface_names
      | map(select(test("^(nebula|wg|wireguard|openvpn|tun|tap)[A-Za-z0-9_.:-]*$")))
      | map(select(. as $ifName | ($explicitOverlayInterfaces | index($ifName)) == null));
    def base_safe:
      has("chain input")
      and has("type filter hook input priority filter; policy drop;")
      and has("iifname \"lo\" accept")
      and has("ct state established,related accept")
      and has("chain forward")
      and has("type filter hook forward priority filter; policy drop;")
      and has("chain output")
      and has("type filter hook output priority filter; policy accept;");
    def overlay_safe:
      (is_overlay_core | not)
      or (
        has("allow-overlay-to-core")
        and (.rules | contains("masquerade") | not)
        and (.rules | contains("tcp option maxseg size set rt mtu") | not)
        and (.rules | contains("eth0") | not)
        and (.rules | contains("eth1") | not)
        and (unexpected_provider_interfaces | length == 0)
      );
    [
      containers
      | select(is_router)
      | . + {
          base_safe: base_safe,
          overlay_safe: overlay_safe,
          unexpected_provider_interfaces: unexpected_provider_interfaces
        }
      | select((.base_safe and .overlay_safe) | not)
    ] as $failed
    | {
        ok: ($failed | length == 0),
        failed: ($failed | map({
          label,
          host,
          name,
          role,
          base_safe,
          overlay_safe,
          unexpected_provider_interfaces
        })),
        checks: {
          all_router_rulesets_fail_closed: ($failed | map(select(.base_safe == false)) | length == 0),
          overlay_cores_do_not_inherit_wan_or_unknown_provider_names: ($failed | map(select(.overlay_safe == false)) | length == 0)
        }
      }
  ' "${dry_json}" > "${result_json}"

  assert_json_checks_ok "network-labs-router-safe-defaults:${label}" "${result_json}"
  rm -f "${result_json}"
}

failures=0

run_label() {
  local label="$1"
  local tmp_dir
  tmp_dir="$(mktemp -d "${TMPDIR:-/tmp}/network-renderer-nixos-safe-defaults.${label}.XXXXXX")"
  trap '[[ -n "${tmp_dir:-}" ]] && rm -rf "${tmp_dir}"' EXIT

  log "Checking router safe defaults for network-labs/examples/${label}"
  render_example "${label}" "${tmp_dir}"
  assert_safe_defaults "${label}" "${tmp_dir}/dry.json" "${tmp_dir}/cpm.json"
  pass "network-labs-router-safe-defaults:${label}"
}

pids=()
pid_labels=()
pid_logs=()

wait_batch() {
  local idx pid rc label log_file

  for idx in "${!pids[@]}"; do
    pid="${pids[$idx]}"
    label="${pid_labels[$idx]}"
    log_file="${pid_logs[$idx]}"

    if wait "${pid}"; then
      rc=0
    else
      rc=$?
    fi

    if [[ -f "${log_file}" ]]; then
      cat "${log_file}"
      rm -f "${log_file}"
    fi

    if (( rc != 0 )); then
      echo "FAIL network-labs-router-safe-defaults:${label} exited ${rc}" >&2
      failures=$((failures + 1))
    fi
  done

  pids=()
  pid_labels=()
  pid_logs=()
}

for label in "${labels[@]}"; do
  log_file="$(mktemp "${TMPDIR:-/tmp}/network-renderer-nixos-safe-defaults.${label}.log.XXXXXX")"
  run_label "${label}" >"${log_file}" 2>&1 &
  pid=$!
  pids+=("${pid}")
  pid_labels+=("${label}")
  pid_logs+=("${log_file}")

  if (( ${#pids[@]} >= test_jobs )); then
    wait_batch
  fi
done

wait_batch

if (( failures > 0 )); then
  fail "network-labs-router-safe-defaults failed ${failures} example(s)"
fi
