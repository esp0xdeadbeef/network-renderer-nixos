from __future__ import annotations

from typing import Dict, Any, List, Tuple


def _sorted_ifaces(eth_map: Dict[str, int]) -> List[Tuple[str, int]]:
    return sorted(eth_map.items(), key=lambda x: x[1])


def _link(ifname: str, eth: int) -> Dict[str, Any]:
    return {
        "ifname": ifname,
        "eth": eth,
    }


def _maybe_link(items: List[Tuple[str, int]], index: int) -> Dict[str, Any] | None:
    if index < 0:
        index = len(items) + index
    if index < 0 or index >= len(items):
        return None
    ifname, eth = items[index]
    return _link(ifname, eth)


def _links(items: List[Tuple[str, int]]) -> List[Dict[str, Any]]:
    return [_link(ifname, eth) for ifname, eth in items]


def _iface_data(node_data: Dict[str, Any], ifname: str) -> Dict[str, Any]:
    interfaces = node_data.get("interfaces", {})
    if not isinstance(interfaces, dict):
        return {}
    iface = interfaces.get(ifname, {})
    return iface if isinstance(iface, dict) else {}


def _filter_links(
    items: List[Tuple[str, int]],
    node_data: Dict[str, Any],
    *,
    kind: str | None = None,
    tenant: str | None = None,
    upstream: str | None = None,
    exclude_kind: str | None = None,
) -> List[Dict[str, Any]]:
    results: List[Dict[str, Any]] = []

    for ifname, eth in items:
        iface = _iface_data(node_data, ifname)

        iface_kind = iface.get("kind")
        iface_tenant = iface.get("tenant")
        iface_upstream = iface.get("upstream")

        if kind is not None and iface_kind != kind:
            continue
        if exclude_kind is not None and iface_kind == exclude_kind:
            continue
        if tenant is not None and iface_tenant != tenant:
            continue
        if upstream is not None and iface_upstream != upstream:
            continue

        results.append(_link(ifname, eth))

    return results


def _first_link(
    items: List[Tuple[str, int]],
    node_data: Dict[str, Any],
    *,
    kind: str | None = None,
    tenant: str | None = None,
    upstream: str | None = None,
    exclude_kind: str | None = None,
) -> Dict[str, Any] | None:
    matches = _filter_links(
        items,
        node_data,
        kind=kind,
        tenant=tenant,
        upstream=upstream,
        exclude_kind=exclude_kind,
    )
    if matches:
        return matches[0]
    return None


def parse_access(
    node_name: str,
    node_data: Dict[str, Any],
    eth_map: Dict[str, int],
) -> Dict[str, Any]:
    items = _sorted_ifaces(eth_map)

    tenant_link = _first_link(items, node_data, kind="tenant", exclude_kind="wan")
    fabric_link = _first_link(items, node_data, exclude_kind="tenant")
    if fabric_link is None:
        fabric_link = _first_link(items, node_data, kind="p2p")

    return {
        "node": node_name,
        "role": "access",
        "links": {
            "fabric": fabric_link,
            "tenant": tenant_link,
            "all": _links(items),
        },
    }


def parse_core(
    node_name: str,
    node_data: Dict[str, Any],
    eth_map: Dict[str, int],
) -> Dict[str, Any]:
    items = _sorted_ifaces(eth_map)

    wan_link = _first_link(items, node_data, kind="wan")
    fabric_link = _first_link(items, node_data, kind="p2p")
    if fabric_link is None:
        fabric_link = _first_link(items, node_data, exclude_kind="wan")

    return {
        "node": node_name,
        "role": "core",
        "links": {
            "fabric": fabric_link,
            "wan": wan_link,
            "all": _links(items),
        },
    }


def parse_wan_peer(
    node_name: str,
    node_data: Dict[str, Any],
    eth_map: Dict[str, int],
) -> Dict[str, Any]:
    items = _sorted_ifaces(eth_map)

    fabric_link = _first_link(items, node_data, kind="wan")
    if fabric_link is None:
        fabric_link = _first_link(items, node_data)

    return {
        "node": node_name,
        "role": "wan-peer",
        "links": {
            "fabric": fabric_link,
            "all": _links(items),
        },
    }


def parse_upstream_selector(
    node_name: str,
    node_data: Dict[str, Any],
    eth_map: Dict[str, int],
) -> Dict[str, Any]:
    items = _sorted_ifaces(eth_map)

    policy_link = _first_link(items, node_data, tenant="loopback")
    if policy_link is None:
        policy_link = _maybe_link(items, -1)

    cores = [
        link
        for link in _links(items)
        if policy_link is None or link["ifname"] != policy_link["ifname"]
    ]

    return {
        "node": node_name,
        "role": "upstream-selector",
        "links": {
            "cores": cores,
            "policy": policy_link,
            "all": _links(items),
        },
    }


def parse_policy(
    node_name: str,
    node_data: Dict[str, Any],
    eth_map: Dict[str, int],
) -> Dict[str, Any]:
    items = _sorted_ifaces(eth_map)

    upstream_selector = _first_link(items, node_data, tenant="loopback")
    if upstream_selector is None:
        upstream_selector = _maybe_link(items, -1)

    accesses = [
        link
        for link in _links(items)
        if upstream_selector is None or link["ifname"] != upstream_selector["ifname"]
    ]

    return {
        "node": node_name,
        "role": "policy",
        "links": {
            "accesses": accesses,
            "upstream_selector": upstream_selector,
            "all": _links(items),
        },
    }
