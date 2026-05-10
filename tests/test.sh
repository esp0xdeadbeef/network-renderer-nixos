#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

if [[ "${NETWORK_REPO_SWEEP:-0}" != "1" && "${NETWORK_REPO_DIRECT_TEST_OK:-0}" != "1" ]]; then
  echo "WARN: direct repo tests are partial; set NETWORK_REPO_DIRECT_TEST_OK=1 for intentional focused runs, or run network-codex-agent/scripts/s-router-test-rebuild-loop.sh for the locked full network-* sweep plus live validation." >&2
fi

source "${repo_root}/tests/lib/test-common.sh"

while IFS= read -r -d '' test_file; do
  printf '==> %s\n' "${test_file#${repo_root}/}"
  bash "${test_file}"
done < <(find "${repo_root}/tests" -maxdepth 1 -type f -name 'test-*.sh' -print0 | sort -z)
