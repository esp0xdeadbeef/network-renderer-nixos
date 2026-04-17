#!/usr/bin/env bash

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

"${repo_root}/tests/cases/external-examples.sh"
"${repo_root}/tests/cases/passing-fixtures.sh"
