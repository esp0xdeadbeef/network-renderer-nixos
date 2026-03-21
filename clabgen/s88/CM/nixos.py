from __future__ import annotations

from pathlib import Path
from typing import Any, Dict, List

from clabgen.models import NodeModel, SiteModel
from clabgen.s88.EM.base import render as render_em
from clabgen.s88.Unit.common import build_node_data
from clabgen.s88.Unit.firewall_context import build_node_firewall_state


_ROUTER_ROLES = {"access", "core", "policy", "upstream-selector", "isp"}


def _sorted_eth_map(node: NodeModel) -> Dict[str, int]:
    return {
        ifname: index
        for index, ifname in enumerate(sorted(node.interfaces.keys()))
    }


def _node_extra(site: SiteModel, node_name: str) -> Dict[str, Any]:
    node = site.nodes[node_name]
    neighbors: List[Dict[str, Any]] = []

    for session in site.bgp_sessions:
        a = session.get("a")
        b = session.get("b")
        rr = session.get("rr")

        if node_name not in {a, b}:
            continue

        peer_name = b if node_name == a else a
        if not isinstance(peer_name, str) or peer_name not in site.nodes:
            continue

        peer = site.nodes[peer_name]

        neighbors.append(
            {
                "peer_name": peer_name,
                "peer_asn": site.bgp_asn,
                "peer_addr4": peer.loopback4,
                "peer_addr6": peer.loopback6,
                "update_source": "lo",
                "route_reflector_client": bool(node_name == rr and peer_name != rr),
            }
        )

    neighbors = sorted(
        neighbors,
        key=lambda item: (
            str(item.get("peer_name") or ""),
            str(item.get("peer_addr4") or ""),
            str(item.get("peer_addr6") or ""),
        ),
    )

    extra: Dict[str, Any] = {
        "loopback": {
            "ipv4": node.loopback4,
            "ipv6": node.loopback6,
        },
        "bgp": {
            "asn": site.bgp_asn,
            "neighbors": neighbors,
        },
    }

    extra.update(
        build_node_firewall_state(
            site=site,
            node_name=node_name,
            node=node,
            eth_map=_sorted_eth_map(node),
        )
    )

    return extra


def _build_exec_cmds(site: SiteModel, node_name: str, node: NodeModel) -> List[str]:
    eth_map = _sorted_eth_map(node)
    extra = _node_extra(site, node_name)
    node_data = build_node_data(
        node_name=node_name,
        node=node,
        eth_map=eth_map,
        extra=extra,
    )

    cmds = render_em(
        node.role,
        node_name,
        node_data,
        eth_map,
        routing_mode=str(node_data.get("routing_mode", "static")),
        disable_dynamic=(str(node_data.get("routing_mode", "static")) != "bgp"),
    )

    return _adapt_exec_cmds_for_nixos(cmds)


def _adapt_exec_cmds_for_nixos(cmds: List[str]) -> List[str]:
    adapted: List[str] = []

    for cmd in cmds:
        if (
            cmd == "sysctl -w net.ipv4.conf.eth0.forwarding=0"
            or cmd == "sysctl -w net.ipv6.conf.eth0.forwarding=0"
        ):
            continue

        if cmd == 'nft add rule inet fw forward iifname "eth0" drop':
            continue

        if cmd == 'nft add rule inet fw forward oifname "eth0" drop':
            continue

        if "restart_cmds = [" in cmd:
            cmd = cmd.replace(
                "restart_cmds = [\n"
                "    ['/usr/lib/frr/frrinit.sh', 'restart'],\n"
                "    ['/etc/init.d/frr', 'restart'],\n"
                "    ['service', 'frr', 'restart'],\n"
                "]\n",
                "restart_cmds = [\n"
                "    ['systemctl', 'restart', 'frr.service'],\n"
                "    ['/usr/lib/frr/frrinit.sh', 'restart'],\n"
                "    ['/etc/init.d/frr', 'restart'],\n"
                "    ['service', 'frr', 'restart'],\n"
                "]\n",
            )

        adapted.append(cmd)

    return adapted


def _needs_frr(node: NodeModel) -> bool:
    return node.role in _ROUTER_ROLES


def _nix_escape(value: str) -> str:
    return value.replace("${", "''${").replace("''", "'''")


def _render_shell_script(cmds: List[str]) -> str:
    lines = ["set -euo pipefail"]
    lines.extend(cmds)
    return "\n".join(_nix_escape(line) for line in lines) + "\n"


def render_node_module(
    site: SiteModel,
    node_name: str,
    node: NodeModel,
    rendered_node_name: str | None = None,
) -> str:
    rendered_name = rendered_node_name or node_name
    exec_cmds = _build_exec_cmds(site, node_name, node)
    script_body = _render_shell_script(exec_cmds)
    service_name = f"generated-network-{rendered_name}"
    needs_frr = "true" if _needs_frr(node) else "false"

    return (
        "{ lib, pkgs, ... }:\n"
        "let\n"
        f"  generatedNetworkScript = pkgs.writeShellScript \"{rendered_name}-network\" ''\n"
        f"{script_body}"
        "  '';\n"
        "in\n"
        "{\n"
        f"  networking.hostName = \"{rendered_name}\";\n"
        "  networking.usePredictableInterfaceNames = false;\n"
        "  boot.kernelParams = [ \"net.ifnames=0\" \"biosdevname=0\" ];\n"
        "  boot.kernel.sysctl = {\n"
        "    \"net.ipv4.conf.all.rp_filter\" = lib.mkDefault 0;\n"
        "    \"net.ipv4.conf.default.rp_filter\" = lib.mkDefault 0;\n"
        "  };\n"
        f"  environment.systemPackages = with pkgs; [ bash coreutils findutils gnugrep gnused iproute2 nftables procps python3 ] ++ lib.optionals {needs_frr} [ frr ];\n"
        f"  systemd.services.\"{service_name}\" = {{\n"
        f"    description = \"Generated network bootstrap for {rendered_name}\";\n"
        "    wantedBy = [ \"multi-user.target\" ];\n"
        "    wants = [ \"systemd-udev-settle.service\" ];\n"
        "    after = [ \"local-fs.target\" \"systemd-udev-settle.service\" ];\n"
        "    before = [ \"network-online.target\" ];\n"
        "    path = with pkgs; [ bash coreutils findutils gnugrep gnused iproute2 nftables procps python3 ] ++ lib.optionals "
        f"{needs_frr} [ frr systemd ];\n"
        "    serviceConfig = {\n"
        "      Type = \"oneshot\";\n"
        "      RemainAfterExit = true;\n"
        "      ExecStart = generatedNetworkScript;\n"
        "    };\n"
        "  };\n"
        "}\n"
    )


def render_node_wrapper_module(
    generated_import: str,
    extra_imports: List[str] | None = None,
) -> str:
    imports = [generated_import]
    imports.extend(
        value
        for value in (extra_imports or [])
        if isinstance(value, str) and value.strip()
    )

    body = "\n".join(f"    {item}" for item in imports)

    return (
        "{ ... }:\n"
        "{\n"
        "  imports = [\n"
        f"{body}\n"
        "  ];\n"
        "}\n"
    )


def write_node_module(
    site: SiteModel,
    node_name: str,
    node: NodeModel,
    out_path: str | Path,
    rendered_node_name: str | None = None,
) -> Path:
    path = Path(out_path)
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(
        render_node_module(
            site=site,
            node_name=node_name,
            node=node,
            rendered_node_name=rendered_node_name,
        ),
        encoding="utf-8",
    )
    return path


def write_node_wrapper_module(
    out_path: str | Path,
    generated_import: str,
    extra_imports: List[str] | None = None,
) -> Path:
    path = Path(out_path)
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(
        render_node_wrapper_module(
            generated_import=generated_import,
            extra_imports=extra_imports,
        ),
        encoding="utf-8",
    )
    return path
