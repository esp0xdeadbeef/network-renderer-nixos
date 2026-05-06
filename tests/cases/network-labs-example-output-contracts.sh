#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "${repo_root}/tests/lib/test-common.sh"

examples_root="${1:-$(flake_input_path network-labs)/examples}"
examples_root="$(realpath "${examples_root}")"

if [[ ! -d "${examples_root}" ]]; then
  fail "missing network-labs examples directory: ${examples_root}"
fi

case_contract() {
  local label="$1"

  expected_hosts='["lab-host"]'
  expected_modes='["static"]'
  expected_uplinks='["wan"]'
  expected_nodes=7
  expected_containers=7
  required_features=''
  forbidden_features=''

  case "${label}" in
    single-wan)
      required_features='public_service_ingress'
      ;;
    single-wan-any-to-any-fw)
      required_features='any_to_any_fw'
      forbidden_features='public_dnat'
      ;;
    single-wan-bgp)
      expected_modes='["bgp"]'
      required_features='bgp public_service_ingress'
      ;;
    single-wan-direct-transit)
      required_features='direct_transit public_service_ingress'
      ;;
    single-wan-ipv6-pd)
      required_features='ipv6_pd_model public_service_ingress'
      ;;
    single-wan-uplink-ebgp)
      expected_modes='["bgp"]'
      required_features='bgp ebgp_uplink public_service_ingress'
      ;;
    single-wan-uplink-static-egress)
      required_features='static_default_route public_service_ingress'
      ;;
    single-wan-vlan-trunk-lanes)
      required_features='vlan_trunk public_service_ingress'
      ;;
    single-wan-with-nebula)
      expected_nodes=8
      expected_containers=8
      expected_uplinks='["nebula","wan"]'
      required_features='overlay'
      forbidden_features='public_dnat'
      ;;
    single-wan-with-nebula-any-to-any-fw)
      expected_nodes=8
      expected_containers=8
      expected_uplinks='["nebula","wan"]'
      required_features='overlay any_to_any_fw'
      forbidden_features='public_dnat'
      ;;
    multi-wan)
      expected_nodes=13
      expected_containers=13
      expected_uplinks='["isp-a","isp-b"]'
      required_features='multi_wan'
      ;;
    multi-wan-dedicated-lanes)
      expected_uplinks='["isp-a","isp-b"]'
      required_features='multi_wan dedicated_lanes'
      ;;
    multi-enterprise)
      expected_nodes=14
      expected_containers=14
      required_features='multi_enterprise'
      ;;
    overlay-east-west)
      expected_nodes=12
      expected_containers=12
      expected_uplinks='["east-west","isp"]'
      required_features='overlay'
      forbidden_features='public_dnat'
      ;;
    priority-stability)
      required_features='dns_policy stable_priorities'
      ;;
    ipv6-pd-downstream-delegation)
      expected_nodes=8
      expected_containers=8
      required_features='ipv6_pd_runtime'
      ;;
    dual-wan-branch-overlay)
      expected_nodes=16
      expected_containers=16
      expected_uplinks='["east-west","isp-a","isp-b","wan"]'
      required_features='overlay dual_wan_branch'
      ;;
    dual-wan-branch-overlay-bgp)
      expected_nodes=16
      expected_containers=16
      expected_modes='["bgp"]'
      expected_uplinks='["east-west","isp-a","isp-b","wan"]'
      required_features='bgp overlay dual_wan_branch'
      ;;
    s-router-overlay-dns-lane-policy)
      expected_hosts='["s-router-hetzner-anywhere","s-router-test"]'
      expected_nodes=26
      expected_containers=26
      expected_modes='["bgp"]'
      expected_uplinks='["east-west","isp-a","isp-b","wan"]'
      required_features='bgp overlay vlan_trunk dns_policy public_dnat'
      ;;
    s-router-public-overlay-service)
      expected_hosts='["s-router-hetzner-anywhere","s-router-test"]'
      expected_nodes=26
      expected_containers=26
      expected_modes='["bgp"]'
      expected_uplinks='["east-west","isp-a","isp-b","wan"]'
      required_features='bgp overlay vlan_trunk dns_policy public_overlay_service'
      ;;
    tri-site-dual-wan-overlay-integration-static)
      expected_nodes=28
      expected_containers=28
      expected_uplinks='["east-west","isp-a","isp-b","site-c-storage","wan"]'
      required_features='overlay vlan_trunk dns_policy tri_site'
      ;;
    tri-site-dual-wan-overlay-integration-bgp)
      expected_nodes=28
      expected_containers=28
      expected_modes='["bgp"]'
      expected_uplinks='["east-west","isp-a","isp-b","site-c-storage","wan"]'
      required_features='bgp overlay vlan_trunk dns_policy tri_site'
      ;;
    *)
      fail "no output contract registered for network-labs example: ${label}"
      ;;
  esac
}

render_example() {
  local label="$1"
  local case_dir="${examples_root}/${label}"
  local intent_path="${case_dir}/intent.nix"
  local inventory_path="${case_dir}/inventory-nixos.nix"
  local output_path="$2"

  [[ -f "${intent_path}" ]] || fail "missing intent.nix for ${label}: ${intent_path}"
  [[ -f "${inventory_path}" ]] || fail "missing inventory-nixos.nix for ${label}: ${inventory_path}"

  build_cpm_json "${intent_path}" "${inventory_path}" "${output_path}/cpm.json"

  REPO_ROOT="${repo_root}" \
  CPM_PATH="${output_path}/cpm.json" \
  INVENTORY_PATH="${inventory_path}" \
    nix eval \
      --extra-experimental-features 'nix-command flakes' \
      --impure --json \
      --expr '
        let
          repoRoot = "path:" + builtins.getEnv "REPO_ROOT";
          cpmPath = builtins.getEnv "CPM_PATH";
          inventoryPath = builtins.getEnv "INVENTORY_PATH";
          flake = builtins.getFlake repoRoot;
        in
        flake.lib.renderer.renderDryConfig {
          inherit cpmPath inventoryPath;
          exampleDir = builtins.dirOf cpmPath;
          debug = true;
        }
      ' \
      > "${output_path}/90-dry-config.json"

  jq -c . "${output_path}/90-dry-config.json" > "${output_path}/90-dry-config.jq-c.jsonl"
}

assert_output_contract() {
  local label="$1"
  local dry_json="$2"
  local result_json
  result_json="$(mktemp)"

  _jq \
    --arg label "${label}" \
    --arg features "${required_features}" \
    --arg forbiddenFeatures "${forbidden_features}" \
    --argjson expectedHosts "${expected_hosts}" \
    --argjson expectedNodes "${expected_nodes}" \
    --argjson expectedContainers "${expected_containers}" \
    --argjson expectedModes "${expected_modes}" \
    --argjson expectedUplinks "${expected_uplinks}" \
    '
      def feature($name): (($features | split(" ")) | index($name)) != null;
      def forbidden($name): (($forbiddenFeatures | split(" ")) | index($name)) != null;
      def sorted_keys: keys | sort;
      def all_rules:
        [(.render.containers // {})[][]?.firewall.ruleset? // empty] | join("\n");
      def route_modes:
        [(.render.sites // {})[][]?.routing.mode? // empty] | unique | sort;
      def uplink_names:
        [(.render.sites // {})[][]?.routing.uplinks? // {} | keys[]] | unique | sort;
      def node_names:
        [(.render.nodes // {})[]?.logicalNode.name] | sort;
      def role_names:
        [(.render.nodes // {})[]?.role] | unique | sort;
      def container_count:
        [(.render.containers // {})[] | keys | length] | add // 0;
      def has_vlan_netdev:
        [(.render.hosts // {})[]?.network.netdevs[]? | select((.netdevConfig.Kind // null) == "vlan")] | length > 0;
      def has_bgp_routing:
        [(.render.sites // {})[][]?.routing? | select((.mode // null) == "bgp" and (.bgp.asn? | type == "number"))] | length > 0;
      def has_multi_wan:
        ((uplink_names | index("isp-a")) != null)
        and ((uplink_names | index("isp-b")) != null)
        and ([node_names[] | select(test("core-isp-a|core-isp-b"))] | length >= 2);
      def has_ipv6_pd_model:
        ([.debug.controlPlane.control_plane_model.data // {} | .[][]? | select(.ipv6? != null)] | length > 0)
        and ([.. | strings | select(. == "dhcpv6" or . == "dhcp" or test("allow-ipv6-nd-ra"))] | length > 0);
      def has_ipv6_pd_runtime:
        ([.debug.controlPlane.control_plane_model.data // {} | .[][]? | select(.ipv6.pd? != null)] | length > 0)
        and ([.. | strings | select(. == "/run/s88-ipv6-pd/wan.prefix")] | length > 0);
      def has_static_default_route:
        [(.render.sites // {})[][]?.routing.uplinks.wan.static.routes.ipv4[]? | select(.prefix == "0.0.0.0/0" and .via == "192.0.2.1")] | length > 0;
      def has_ebgp_uplink:
        [(.render.sites // {})[][]?.routing.uplinks.wan.bgp? | select(.peerAsn == 64512 and .peerAddr4 == "203.0.113.1/32")] | length > 0;
      def has_dedicated_lanes:
        ([.render.sites // {} | .[][]?.transit? | select(.dedicatedLanes == true)] | length > 0)
        and ([.render.sites // {} | .[][]?.transit.adjacencies[]?.name | select(test("--access-.*--uplink-"))] | length > 0);
      def has_multi_enterprise_disambiguation:
        ((.render.sites // {}) | keys | sort) == ["esp0xdeadbeef","esp0xdeadbeef-2"]
        and ((node_names | group_by(.) | map(select(length > 1)) | length) > 0)
        and ([.render.containers."lab-host" | keys[] | select(test("^esp0xdeadbeef(-2)?-site-[ab]-esp0xdeadbeef"))] | length == 14);
      def has_any_to_any_fw:
        all_rules | test("allow-mgmt-internal|allow-.*any|accept comment");
      def has_overlay:
        ((uplink_names | any(. == "east-west" or . == "nebula" or . == "site-c-storage"))
          and ([node_names[] | select(test("nebula|core-nebula"))] | length > 0));
      def has_dns_policy:
        all_rules | test("dport \\{ 53 \\}|dport 53|deny-direct-dns-egress|allow-dns-service");
      def has_public_dnat:
        all_rules | test("dnat");
      def has_public_service_ingress:
        (all_rules | test("dnat"))
        and (all_rules | test("allow-wan-to-jump-host"))
        and (all_rules | test("allow-wan-to-admin-web"))
        and (all_rules | test("tcp dport 22"))
        and (all_rules | test("tcp dport 80"))
        and (all_rules | test("tcp dport 443"));
      def has_public_overlay_service:
        (all_rules | test("dnat to 10\\.90\\.10\\.100"))
        and (all_rules | test("udp dport 4242|tcp dport 4242"))
        and (all_rules | test("allow-sitec-wan-to-dmz-nebula"));
      def has_tri_site:
        ((.render.sites // {}) | keys | sort) == ["esp0xdeadbeef","espbranch"]
        and (([.render.sites.esp0xdeadbeef | keys[]] | sort) == ["site-a","site-c"])
        and (([.render.sites.espbranch | keys[]] | sort) == ["site-b"]);
      def has_direct_transit:
        [(.render.sites // {})[][]?.transit.adjacencies[]?.name | select(test("core-wan-s-router-upstream-selector|downstream-selector-s-router-policy"))] | length >= 2;
      def has_dual_wan_branch:
        ([node_names[] | select(test("^s-router-core-isp-[ab]$|^b-router-core-wan$|^b-router-core-nebula$"))] | length >= 4)
        and ((uplink_names | index("isp-a")) != null)
        and ((uplink_names | index("isp-b")) != null)
        and ((uplink_names | index("wan")) != null);
      def stable_priorities:
        [all_rules | scan("priority [0-9]+|comment \\\"[^\\\"]+\\\"")] | length > 0;

      . as $dry
      | {
          top_level_shape:
            (($dry | keys | sort) == ["debug","metadata","render"]),
          no_metadata_warnings_or_alarms:
            (($dry.metadata.warnings // []) == [] and ($dry.metadata.alarms // []) == []),
          no_render_container_warnings_or_alarms:
            ([($dry.render.containers // {})[][]? | select(((.warnings // []) | length) > 0 or ((.alarms // []) | length) > 0)] | length == 0),
          source_paths_present:
            (($dry.metadata.sourcePaths.cpmPath // "") != ""
             and ($dry.metadata.sourcePaths.inventoryPath // "") != ""
             and ($dry.metadata.sourcePaths.repoRoot // "") != ""),
          expected_hosts:
            (($dry.render.hosts // {} | keys | sort) == $expectedHosts),
          expected_node_count:
            (($dry.render.nodes // {} | keys | length) == $expectedNodes),
          expected_container_count:
            (container_count == $expectedContainers),
          expected_routing_modes:
            (route_modes == $expectedModes),
          expected_uplinks:
            (uplink_names == $expectedUplinks),
          required_roles_present:
            ((role_names | sort) == ["access","core","downstream-selector","policy","upstream-selector"]),
          render_nodes_cover_debug_targets:
            (($dry.render.nodes // {} | sorted_keys) == ($dry.debug.normalizedRuntimeTargets // {} | sorted_keys)),
          render_hosts_cover_debug_hosts:
            (($dry.render.hosts // {} | sorted_keys) == ($dry.debug.hostRenderings // {} | sorted_keys)),
          render_container_hosts_cover_hosts:
            (($dry.render.containers // {} | sorted_keys) == ($dry.render.hosts // {} | sorted_keys)),
          all_nodes_have_existing_host:
            ([($dry.render.nodes // {})[]? | (.deploymentHostName // null) as $host | ($host != null and (($dry.render.hosts // {}) | has($host)))] | all),
          all_containers_have_identity:
            ([($dry.render.containers // {})[][]? | ((.specialArgs.unitName // "") != "" and (.specialArgs.deploymentHostName // "") != "")] | all),
          host_network_fragments_not_empty:
            ([($dry.render.hosts // {})[]? | (((.network.bridges // {}) | length) > 0 and ((.network.networks // {}) | length) > 0)] | all),
          feature_bgp:
            ((feature("bgp") and has_bgp_routing) or ((feature("bgp") | not) and (has_bgp_routing | not))),
          feature_overlay:
            ((feature("overlay") | not) or has_overlay),
          feature_vlan_trunk:
            ((feature("vlan_trunk") | not) or has_vlan_netdev),
          feature_multi_wan:
            ((feature("multi_wan") | not) or has_multi_wan),
          feature_ipv6_pd_model:
            ((feature("ipv6_pd_model") | not) or has_ipv6_pd_model),
          feature_ipv6_pd_runtime:
            ((feature("ipv6_pd_runtime") | not) or has_ipv6_pd_runtime),
          feature_static_default_route:
            ((feature("static_default_route") | not) or has_static_default_route),
          feature_ebgp_uplink:
            ((feature("ebgp_uplink") | not) or has_ebgp_uplink),
          feature_dedicated_lanes:
            ((feature("dedicated_lanes") | not) or has_dedicated_lanes),
          feature_multi_enterprise:
            ((feature("multi_enterprise") | not) or has_multi_enterprise_disambiguation),
          feature_any_to_any_fw:
            ((feature("any_to_any_fw") | not) or has_any_to_any_fw),
          feature_dns_policy:
            ((feature("dns_policy") | not) or has_dns_policy),
          feature_public_dnat:
            ((feature("public_dnat") | not) or has_public_dnat),
          feature_public_service_ingress:
            ((feature("public_service_ingress") | not) or has_public_service_ingress),
          feature_public_overlay_service:
            ((feature("public_overlay_service") | not) or has_public_overlay_service),
          feature_tri_site:
            ((feature("tri_site") | not) or has_tri_site),
          feature_direct_transit:
            ((feature("direct_transit") | not) or has_direct_transit),
          feature_dual_wan_branch:
            ((feature("dual_wan_branch") | not) or has_dual_wan_branch),
          feature_stable_priorities:
            ((feature("stable_priorities") | not) or stable_priorities),
          forbidden_public_dnat:
            ((forbidden("public_dnat") | not) or (has_public_dnat | not))
        } as $checks
      | {
          ok: ([$checks[]] | all(. == true)),
          checks: $checks,
          failed: ($checks | to_entries | map(select(.value != true) | .key))
        }
    ' "${dry_json}" > "${result_json}"

  assert_json_checks_ok "network-labs-output:${label}" "${result_json}"
  rm -f "${result_json}"
}

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

for label in "${labels[@]}"; do
  case_contract "${label}"
  tmp_dir="$(mktemp -d "${TMPDIR:-/tmp}/network-renderer-nixos-example-output.XXXXXX")"
  trap 'rm -rf "${tmp_dir}"' RETURN

  log "Rendering network-labs/examples/${label}"
  render_example "${label}" "${tmp_dir}"
  assert_output_contract "${label}" "${tmp_dir}/90-dry-config.jq-c.jsonl"

  trap - RETURN
  rm -rf "${tmp_dir}"
  pass "network-labs-output:${label}"
done
