#!/usr/bin/env bash
set -euo pipefail

example_repo="$(nix flake prefetch github:esp0xdeadbeef/network-labs --json | jq -r .storePath)"
INPUT_NIX="$example_repo/examples/single-wan-with-nebula/intent.nix"

exec nix run .#generate-nixos-config -- "$INPUT_NIX"
