#!/usr/bin/env python3
from __future__ import annotations

import os
import sys
from pathlib import Path

from clabgen.s88.enterprise.site_loader import load_sites
from clabgen.s88.CM.nixos import write_node_module


def _usage() -> None:
    print("usage: generate-nixos-config.py <solver.json> <output-dir> [routing-mode]")


def _write_site_default(site_dir: Path, node_names: list[str]) -> None:
    imports = "\n".join(f"    ./{name}.nix" for name in node_names)
    content = (
        "{ ... }:\n"
        "{\n"
        "  imports = [\n"
        f"{imports}\n"
        "  ];\n"
        "}\n"
    )
    (site_dir / "default.nix").write_text(content, encoding="utf-8")


def _write_top_default(output_dir: Path, site_defaults: list[Path]) -> None:
    rels = [p.relative_to(output_dir) for p in site_defaults]
    imports = "\n".join(f"    ./{rel.as_posix()}" for rel in rels)
    content = (
        "{ ... }:\n"
        "{\n"
        "  imports = [\n"
        f"{imports}\n"
        "  ];\n"
        "}\n"
    )
    (output_dir / "default.nix").write_text(content, encoding="utf-8")


def main() -> None:
    if len(sys.argv) < 3:
        _usage()
        raise SystemExit(1)

    solver_json = Path(sys.argv[1]).resolve()
    output_dir = Path(sys.argv[2]).resolve()

    routing_mode = os.environ.get("CLABGEN_ROUTING_MODE", "static").strip().lower()
    if len(sys.argv) >= 4:
        routing_mode = sys.argv[3].strip().lower()

    if routing_mode not in {"static", "bgp"}:
        routing_mode = "static"

    os.environ["CLABGEN_ROUTING_MODE"] = routing_mode
    output_dir.mkdir(parents=True, exist_ok=True)

    sites = load_sites(solver_json)
    written_site_defaults: list[Path] = []

    for site_key in sorted(sites.keys()):
        site = sites[site_key]
        site_dir = output_dir / site.enterprise / site.site
        site_dir.mkdir(parents=True, exist_ok=True)

        written_nodes: list[str] = []

        for node_name, node in sorted(site.nodes.items()):
            out_path = site_dir / f"{node_name}.nix"
            write_node_module(
                site=site,
                node_name=node_name,
                node=node,
                out_path=out_path,
                rendered_node_name=node_name,
            )
            written_nodes.append(node_name)

        _write_site_default(site_dir, written_nodes)
        written_site_defaults.append(site_dir / "default.nix")

    _write_top_default(output_dir, written_site_defaults)


if __name__ == "__main__":
    main()
