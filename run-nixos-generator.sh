#!/usr/bin/env bash
set -euo pipefail

INPUT_JSON="renderer-inputs.json"
COMPILER_OUT="output-compiler-signed.json"
SITES_ONLY="sites-only.json"
SOLVER_OUT="output-solver-signed.json"

echo "[*] Running compiler..."
nix run .#compiler "$INPUT_JSON" > "$COMPILER_OUT"

echo "[*] Extracting .sites for solver..."
jq '.sites' "$COMPILER_OUT" > "$SITES_ONLY"

echo "[*] Running solver..."
nix run .#solver "$SITES_ONLY" > "$SOLVER_OUT"

echo "[*] Generating NixOS configs..."
./generate-nixos-config.py "$SOLVER_OUT" ./nixos-out
