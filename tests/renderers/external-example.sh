#!/usr/bin/env bash

set -euo pipefail

artifact_dir="$1"

[[ -e "${artifact_dir}/network-artifacts/control-plane-model.json" ]]

find "${artifact_dir}/network-artifacts" \( -type l -o -type f \) | sort >/dev/null
