#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "${repo_root}/tests/lib/test-common.sh"

labs_root="$(flake_input_path network-labs)"
example_dir="${labs_root}/examples/dual-wan-branch-overlay"
intent_nix="${example_dir}/intent.nix"
inventory_nix="${example_dir}/inventory-nixos.nix"

if [[ ! -f "${intent_nix}" || ! -f "${inventory_nix}" ]]; then
  fail "missing dual-wan-branch-overlay example inputs in network-labs flake input"
fi

tmp_dir="$(mktemp -d "${TMPDIR:-/tmp}/network-renderer-nixos-host-veth.XXXXXX")"
trap 'rm -rf "${tmp_dir}"' EXIT

log "Rendering dual-wan-branch-overlay for host-veth sufficiency checks"
(
  cd "${tmp_dir}"
  build_cpm_json "${intent_nix}" "${inventory_nix}" "${tmp_dir}/cpm.json"

  nix run \
    --no-write-lock-file \
    --extra-experimental-features 'nix-command flakes' \
    "${repo_root}"#render-dry-config \
    -- \
    --debug \
    "${tmp_dir}/cpm.json" \
    >/dev/null
)

render_json="${tmp_dir}/90-render.json"
dry_json="${tmp_dir}/90-dry-config.json"

# Consumer sufficiency guard: host veth names must be globally unique.
duplicate_host_veths="$(
  jq -r '
    [
      .containers
      | to_entries[]
      | .value
      | to_entries[]
      | .value
      | (.extraVeths // {})
      | keys[]
    ]
    | group_by(.)
    | map(select(length > 1) | .[0])
    | .[]
  ' "${render_json}" || true
)"

if [[ -n "${duplicate_host_veths}" ]]; then
  fail "duplicate host veth names in rendered output: ${duplicate_host_veths}"
fi

# Guard: all p2p interfaces must carry explicit adapter names and those names must
# be unique across the rendered deployment (consumer link selectors rely on this).
missing_p2p_adapter_names="$(
  jq -r '
    [
      .debug.hostRenderings
      | to_entries[]
      | .value.attachTargets[]?
      | .interface
      | select((.connectivity.sourceKind // null) == "p2p")
      | .adapterName
      | select(. == null or . == "")
    ]
    | length
  ' "${dry_json}"
)"

if [[ "${missing_p2p_adapter_names}" != "0" ]]; then
  fail "p2p interfaces missing adapterName in rendered output: count=${missing_p2p_adapter_names}"
fi

duplicate_p2p_adapter_names="$(
  jq -r '
    [
      .debug.hostRenderings
      | to_entries[]
      | .value.attachTargets[]?
      | .interface
      | select((.connectivity.sourceKind // null) == "p2p")
      | .adapterName
    ]
    | group_by(.)
    | map(select(length > 1) | .[0])
    | .[]
  ' "${dry_json}" || true
)"

if [[ -n "${duplicate_p2p_adapter_names}" ]]; then
  fail "duplicate p2p adapter names in rendered output: ${duplicate_p2p_adapter_names}"
fi

# Reachability sufficiency guard: inside each site, every node must have an
# internal-reachability route to every other node loopback.
missing_site_loopback_routes="$(
  jq -r '
    def nodeLoopbacks:
      [
        .debug.controlPlane.forwardingModel.enterprise
        | to_entries[] as $ent
        | $ent.value.site
        | to_entries[] as $site
        | $site.value.nodes
        | to_entries[]
        | {
            node: .key,
            site: $site.key,
            loop4: (.value.loopback.ipv4 | split("/") | .[0])
          }
      ];

    def nodeInternalRouteDsts:
      reduce (
        [
          .debug.hostRenderings
          | to_entries[]
          | .value.attachTargets[]?
          | .interface
          | select(.logicalNode != null)
        ][]
      ) as $iface ({ };
        .[$iface.logicalNode] = (
          (.[$iface.logicalNode] // [])
          + [
              ($iface.routes // [])[]
              | select(.intent.kind == "internal-reachability")
              | .dst
              | split("/") | .[0]
            ]
        )
      );

    (nodeLoopbacks) as $nodes
    | (nodeInternalRouteDsts) as $routeDsts
    | [
        $nodes[] as $src
        | $nodes[] as $dst
        | select($src.node != $dst.node)
        | select($src.site == $dst.site)
        | select((($routeDsts[$src.node] // []) | index($dst.loop4)) == null)
        | "\($src.site): \($src.node) -> \($dst.node) (missing \($dst.loop4))"
      ]
    | .[]
  ' "${dry_json}" || true
)"

if [[ -n "${missing_site_loopback_routes}" ]]; then
  fail "missing in-site loopback routes in rendered output: ${missing_site_loopback_routes}"
fi

# Specific regression guard for dual ISP cores: both cores must render disjoint extraVeth sets.
jq -e '
  .containers
  | to_entries[]
  | .value as $hostContainers
  | select(($hostContainers | has("s-router-core-isp-a")) and ($hostContainers | has("s-router-core-isp-b")))
  | ($hostContainers["s-router-core-isp-a"].extraVeths // {}) as $a
  | ($hostContainers["s-router-core-isp-b"].extraVeths // {}) as $b
  | ($a | keys | length) > 0
    and ($b | keys | length) > 0
    and ((($a | keys) + ($b | keys) | length) == (((($a | keys) + ($b | keys)) | unique | length)))
' "${render_json}" >/dev/null || fail "dual ISP core extraVeth output is insufficient for consumer attachment"

pass "host-veth consumer sufficiency"
