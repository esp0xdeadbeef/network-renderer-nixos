# ./generate-nixos-config.py
#!/usr/bin/env python3
from __future__ import annotations

import sys
import os
from pathlib import Path
import importlib.util


def _load_parser():
    parser_file = Path.cwd() / "clabgen" / "parse-solver-json.py"

    spec = importlib.util.spec_from_file_location("clabgen.parse_solver_json", parser_file)
    module = importlib.util.module_from_spec(spec)
    assert spec.loader is not None
    spec.loader.exec_module(module)
    return module


def main() -> None:
    if len(sys.argv) < 3:
        print(
            "usage: generate-nixos-config.py <solver.json> <output-dir> [routing-mode]"
        )
        raise SystemExit(1)

    solver_json = sys.argv[1]
    output_dir = sys.argv[2]

    routing_mode = os.environ.get("CLABGEN_ROUTING_MODE", "static").strip().lower()
    if len(sys.argv) >= 4:
        routing_mode = sys.argv[3].strip().lower()

    if routing_mode not in {"static", "bgp"}:
        routing_mode = "static"

    os.environ["CLABGEN_ROUTING_MODE"] = routing_mode

    os.makedirs(output_dir, exist_ok=True)

    parser = _load_parser()

    # Reuse same pipeline but only emit nixos configs
    parser.write_nixos_outputs(solver_json, output_dir)


if __name__ == "__main__":
    main()
