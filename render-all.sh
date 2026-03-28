#!/usr/bin/env bash
set -euo pipefail

if [ "$#" -gt 1 ]; then
  echo "usage: ./render-all.sh [path-to-network-labs-or-examples]" >&2
  exit 1
fi

if [ "$#" -eq 1 ]; then
  source_root="$(realpath "$1")"
else
  source_root="$(
    nix flake prefetch \
      --extra-experimental-features 'nix-command flakes' \
      github:esp0xdeadbeef/network-labs \
      --json | jq -r .storePath
  )"
fi

if [ -d "$source_root/examples" ]; then
  search_root="$source_root/examples"
else
  search_root="$source_root"
fi

find "$search_root" -name intent.nix -type f | sort | while read -r intent_path; do
  inventory_path="$(dirname "$intent_path")/inventory.nix"

  echo "[*] Running for $intent_path"

  rm -f \
    ./00-*.json \
    ./01-*.json \
    ./02-*.json \
    ./03-*.json \
    ./04-*.json \
    ./10-*.json \
    ./25-*.json \
    ./30-*.json \
    ./90-*.json

  if [ ! -f "$inventory_path" ]; then
    echo
    echo "[!] Missing inventory for: $intent_path"
    echo "[!] Expected sibling file: $inventory_path"
    exit 1
  fi

  if ! nix run \
    --no-write-lock-file \
    --extra-experimental-features 'nix-command flakes' \
    .#render-dry-config \
    -- \
    --debug \
    "$intent_path" \
    "$inventory_path"
  then
    echo
    echo "[!] Generation failed for: $intent_path"
    echo "[!] Dumping generated JSON artifacts:"
    echo

    have_artifacts=false

    for j in ./[0-9][0-9]-*.json; do
      [ -e "$j" ] || continue
      have_artifacts=true
      echo "===== $j ====="
      jq -c . "$j" 2>/dev/null || cat "$j"
      echo
    done

    if [ "$have_artifacts" = false ]; then
      echo "[!] No generated JSON artifacts were produced; dumping source inputs:"
      echo

      echo "===== $intent_path ====="
      cat "$intent_path"
      echo

      echo "===== $inventory_path ====="
      cat "$inventory_path"
      echo
    fi

    exit 1
  fi
done
