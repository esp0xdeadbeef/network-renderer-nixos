#!/usr/bin/env python3
import ipaddress
import json
import sys
from collections import Counter, defaultdict


def fail(message):
    print(message, file=sys.stderr)
    sys.exit(1)


def load_json(path):
    with open(path, encoding="utf-8") as handle:
        return json.load(handle)


def host_veth_names(render_json):
    for host_containers in render_json.get("containers", {}).values():
        for container in host_containers.values():
            yield from (container.get("extraVeths") or {}).keys()


def p2p_interfaces(dry_json):
    for host in dry_json.get("debug", {}).get("hostRenderings", {}).values():
        for target in host.get("attachTargets", []) or []:
            iface = target.get("interface") or {}
            if (iface.get("connectivity") or {}).get("sourceKind") == "p2p":
                yield iface


def logical_interfaces(dry_json):
    for host in dry_json.get("debug", {}).get("hostRenderings", {}).values():
        for target in host.get("attachTargets", []) or []:
            iface = target.get("interface") or {}
            if iface.get("logicalNode"):
                yield iface


def node_loopbacks(dry_json):
    enterprise = (
        dry_json.get("debug", {})
        .get("controlPlane", {})
        .get("forwardingModel", {})
        .get("enterprise", {})
    )
    for enterprise_data in enterprise.values():
        for site_name, site_data in (enterprise_data.get("site") or {}).items():
            for node_name, node_data in (site_data.get("nodes") or {}).items():
                loopback = (node_data.get("loopback") or {}).get("ipv4")
                if loopback:
                    yield {
                        "node": node_name,
                        "site": site_name,
                        "loop4": ipaddress.ip_interface(loopback).ip,
                    }


def route_contains(route_dst, ip):
    try:
        return ip in ipaddress.ip_network(route_dst, strict=False)
    except ValueError:
        return False


def assert_unique(values, message):
    duplicates = sorted(name for name, count in Counter(values).items() if count > 1)
    if duplicates:
        fail(f"{message}: {', '.join(duplicates)}")


def assert_p2p_adapters(dry_json):
    adapters = []
    missing = 0
    for iface in p2p_interfaces(dry_json):
        adapter = iface.get("adapterName")
        if not adapter:
            missing += 1
        else:
            adapters.append(adapter)
    if missing:
        fail(f"p2p interfaces missing adapterName in rendered output: count={missing}")
    assert_unique(adapters, "duplicate p2p adapter names in rendered output")


def assert_site_loopback_routes(dry_json):
    routes_by_node = defaultdict(list)
    for iface in logical_interfaces(dry_json):
        node = iface["logicalNode"]
        for route in iface.get("routes", []) or []:
            if (route.get("intent") or {}).get("kind") == "internal-reachability":
                dst = route.get("dst")
                if dst:
                    routes_by_node[node].append(dst)

    nodes = list(node_loopbacks(dry_json))
    missing = []
    for src in nodes:
        for dst in nodes:
            if src["node"] == dst["node"] or src["site"] != dst["site"]:
                continue
            if not any(route_contains(route, dst["loop4"]) for route in routes_by_node[src["node"]]):
                missing.append(
                    f"{src['site']}: {src['node']} -> {dst['node']} "
                    f"(missing {dst['loop4']})"
                )
    if missing:
        fail("missing in-site loopback routes in rendered output: " + "\n".join(missing))


def assert_dual_isp_veths(render_json):
    for host_containers in render_json.get("containers", {}).values():
        if "s-router-core-isp-a" not in host_containers or "s-router-core-isp-b" not in host_containers:
            continue
        a_keys = set((host_containers["s-router-core-isp-a"].get("extraVeths") or {}).keys())
        b_keys = set((host_containers["s-router-core-isp-b"].get("extraVeths") or {}).keys())
        if a_keys and b_keys and a_keys.isdisjoint(b_keys):
            return
    fail("dual ISP core extraVeth output is insufficient for consumer attachment")


def main():
    if len(sys.argv) != 3:
        fail("usage: check-host-veth-consumer-sufficiency.py RENDER_JSON DRY_JSON")
    render_json = load_json(sys.argv[1])
    dry_json = load_json(sys.argv[2])
    assert_unique(host_veth_names(render_json), "duplicate host veth names in rendered output")
    assert_p2p_adapters(dry_json)
    assert_site_loopback_routes(dry_json)
    assert_dual_isp_veths(render_json)


if __name__ == "__main__":
    main()
