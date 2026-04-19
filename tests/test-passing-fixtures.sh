#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# External tests first (matches how this repo is used in prod).
"${repo_root}/tests/cases/external-examples.sh"

# render-all.sh used to fail-fast on warnings, which makes it hard to use for
# scanning external examples (some warning alarms are upstream/missing CPM data).
# Keep a smoke test that ensures render-all can run a known-warning example and
# still exit 0 by default.
if [[ -d /home/deadbeef/github/network-labs/examples/multi-enterprise ]]; then
  echo "==> Smoke: render-all.sh should not fail on warnings by default"
  "${repo_root}/render-all.sh" "/home/deadbeef/github/network-labs/examples/multi-enterprise"
fi

# Keep at least one in-repo fixture for repeatable CI-like checks.
"${repo_root}/tests/cases/passing-fixtures.sh" "$@"
