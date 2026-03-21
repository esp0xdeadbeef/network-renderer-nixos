# ./generate-nixos-config.py
#!/usr/bin/env python3
from __future__ import annotations

import json
import os
import sys
from pathlib import Path
from typing import Any, Dict, List

from clabgen.s88.enterprise.site_loader import load_sites
from clabgen.s88.CM.nixos import write_node_module, write_node_wrapper_module


def _usage() -> None:
    print("usage: generate-nixos-config.py <solver.json> <output-dir> [routing-mode]")


def _load_renderer_inventory(base_dir: Path) -> Dict[str, Any]:
    inventory_file = base_dir / "renderer-inputs.json"

    if not inventory_file.exists():
        return {}

    with inventory_file.open() as f:
        data = json.load(f)

    if not isinstance(data, dict):
        raise ValueError("renderer-inputs.json top-level must be an object")

    return data


def _site_key(enterprise: str, site: str) -> str:
    return f"{enterprise}-{site}"


def _normalize_import_list(value: Any) -> List[str]:
    if isinstance(value, str) and value.strip():
        return [value.strip()]

    if not isinstance(value, list):
        return []

    result: List[str] = []
    for item in value:
        if isinstance(item, str) and item.strip():
            result.append(item.strip())
    return result


def _inventory_nixos_compat(renderer_inventory: Dict[str, Any]) -> Dict[str, Any]:
    nixos = renderer_inventory.get("nixos", {})
    if not isinstance(nixos, dict):
        return {}
    compat = nixos.get("compat", {})
    return compat if isinstance(compat, dict) else {}


def _dedupe(items: List[str]) -> List[str]:
    out: List[str] = []
    seen: set[str] = set()

    for item in items:
        if item in seen:
            continue
        seen.add(item)
        out.append(item)

    return out


def _resolve_inventory_imports(
    renderer_inventory: Dict[str, Any],
    *,
    enterprise: str,
    site: str,
    node_name: str | None = None,
) -> List[str]:
    compat = _inventory_nixos_compat(renderer_inventory)
    imports: List[str] = []

    imports.extend(_normalize_import_list(compat.get("imports")))

    sites_obj = compat.get("sites", {})
    if isinstance(sites_obj, dict):
        for key in (site, _site_key(enterprise, site), f"{enterprise}/{site}"):
            site_obj = sites_obj.get(key)
            if not isinstance(site_obj, dict):
                continue

            imports.extend(_normalize_import_list(site_obj.get("imports")))

            if node_name is not None:
                nodes_obj = site_obj.get("nodes", {})
                if isinstance(nodes_obj, dict):
                    imports.extend(_normalize_import_list(nodes_obj.get(node_name)))

    nodes_obj = compat.get("nodes", {})
    if node_name is not None and isinstance(nodes_obj, dict):
        imports.extend(_normalize_import_list(nodes_obj.get(node_name)))

    return _dedupe(imports)


def _conventional_compat_candidates(
    repo_root: Path,
    *,
    enterprise: str,
    site: str,
    node_name: str | None = None,
) -> List[Path]:
    candidates: List[Path] = [
        repo_root / "compat" / "nixos" / "default.nix",
        repo_root / "compat" / "nixos" / enterprise / "default.nix",
        repo_root / "compat" / "nixos" / enterprise / site / "default.nix",
        repo_root / "compat" / "nixos" / _site_key(enterprise, site) / "default.nix",
    ]

    if node_name is not None:
        candidates.extend(
            [
                repo_root / "compat" / "nixos" / "nodes" / f"{node_name}.nix",
                repo_root / "compat" / "nixos" / enterprise / "nodes" / f"{node_name}.nix",
                repo_root / "compat" / "nixos" / enterprise / site / "nodes" / f"{node_name}.nix",
                repo_root / "compat" / "nixos" / _site_key(enterprise, site) / "nodes" / f"{node_name}.nix",
            ]
        )

    return candidates


def _render_import_path(from_dir: Path, target: Path) -> str:
    rel = os.path.relpath(target, from_dir)
    rel_posix = Path(rel).as_posix()
    if not rel_posix.startswith("."):
        rel_posix = f"./{rel_posix}"
    return rel_posix


def _resolve_node_extra_imports(
    *,
    repo_root: Path,
    renderer_inventory: Dict[str, Any],
    wrapper_dir: Path,
    enterprise: str,
    site: str,
    node_name: str,
) -> List[str]:
    imports: List[str] = []

    for raw in _resolve_inventory_imports(
        renderer_inventory,
        enterprise=enterprise,
        site=site,
        node_name=node_name,
    ):
        target = Path(raw)
        if not target.is_absolute():
            target = (repo_root / target).resolve()
        if target.exists():
            imports.append(_render_import_path(wrapper_dir, target))

    for candidate in _conventional_compat_candidates(
        repo_root,
        enterprise=enterprise,
        site=site,
        node_name=node_name,
    ):
        if candidate.exists():
            imports.append(_render_import_path(wrapper_dir, candidate))

    return _dedupe(imports)


def _resolve_site_extra_imports(
    *,
    repo_root: Path,
    renderer_inventory: Dict[str, Any],
    site_dir: Path,
    enterprise: str,
    site: str,
) -> List[str]:
    imports: List[str] = []

    for raw in _resolve_inventory_imports(
        renderer_inventory,
        enterprise=enterprise,
        site=site,
        node_name=None,
    ):
        target = Path(raw)
        if not target.is_absolute():
            target = (repo_root / target).resolve()
        if target.exists():
            imports.append(_render_import_path(site_dir, target))

    return _dedupe(imports)


def _write_site_default(
    site_dir: Path,
    node_names: List[str],
    extra_imports: List[str] | None = None,
) -> None:
    imports_list = [f"./{name}.nix" for name in node_names]
    imports_list.extend(extra_imports or [])
    imports = "\n".join(f"    {item}" for item in imports_list)
    content = (
        "{ ... }:\n"
        "{\n"
        "  imports = [\n"
        f"{imports}\n"
        "  ];\n"
        "}\n"
    )
    (site_dir / "default.nix").write_text(content, encoding="utf-8")


def _write_top_default(output_dir: Path, site_defaults: List[Path]) -> None:
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
    repo_root = Path(__file__).resolve().parent
    renderer_inventory = _load_renderer_inventory(repo_root)

    routing_mode = os.environ.get("CLABGEN_ROUTING_MODE", "static").strip().lower()
    if len(sys.argv) >= 4:
        routing_mode = sys.argv[3].strip().lower()

    if routing_mode not in {"static", "bgp"}:
        routing_mode = "static"

    os.environ["CLABGEN_ROUTING_MODE"] = routing_mode
    output_dir.mkdir(parents=True, exist_ok=True)

    sites = load_sites(solver_json, renderer_inventory=renderer_inventory)
    written_site_defaults: List[Path] = []

    for site_key in sorted(sites.keys()):
        site = sites[site_key]
        site_dir = output_dir / site.enterprise / site.site
        generated_dir = site_dir / "generated"
        site_dir.mkdir(parents=True, exist_ok=True)
        generated_dir.mkdir(parents=True, exist_ok=True)

        written_nodes: List[str] = []

        for node_name, node in sorted(site.nodes.items()):
            generated_out_path = generated_dir / f"{node_name}.nix"
            wrapper_out_path = site_dir / f"{node_name}.nix"

            write_node_module(
                site=site,
                node_name=node_name,
                node=node,
                out_path=generated_out_path,
                rendered_node_name=node_name,
            )

            extra_imports = _resolve_node_extra_imports(
                repo_root=repo_root,
                renderer_inventory=renderer_inventory,
                wrapper_dir=site_dir,
                enterprise=site.enterprise,
                site=site.site,
                node_name=node_name,
            )

            write_node_wrapper_module(
                out_path=wrapper_out_path,
                generated_import=f"./generated/{node_name}.nix",
                extra_imports=extra_imports,
            )

            written_nodes.append(node_name)

        site_extra_imports = _resolve_site_extra_imports(
            repo_root=repo_root,
            renderer_inventory=renderer_inventory,
            site_dir=site_dir,
            enterprise=site.enterprise,
            site=site.site,
        )
        _write_site_default(site_dir, written_nodes, extra_imports=site_extra_imports)
        written_site_defaults.append(site_dir / "default.nix")

    _write_top_default(output_dir, written_site_defaults)


if __name__ == "__main__":
    main()
