#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${repo_root}/tests/lib/test-common.sh"

tmp_dir="$(mktemp -d "${TMPDIR:-/tmp}/s88-structural-keywords.XXXXXX")"
trap 'rm -rf "${tmp_dir}"' EXIT

scan_file() {
  local label="$1"
  local pattern="$2"
  local output="$3"

  (
    cd "${repo_root}"
    rg -n --glob '*.nix' "${pattern}" s88 || true
  ) | awk -F: '
    {
      line = $0
      text = $0
      sub(/^[^:]+:[0-9]+:/, "", text)
      if (text ~ /^[[:space:]]*import[[:space:]]/) next
      if (text ~ /=[[:space:]]*import[[:space:]]/) next
      if (line ~ /^s88\/Unit\/mapping\/runtime-targets\/interfaces\/classification\.nix:/) next
      print line
    }
  ' >"${output}"

  if [[ -s "${output}" ]]; then
    local count
    count="$(wc -l <"${output}" | tr -d ' ')"
    echo "FAIL s88-structural-keywords:${label}: ${count} implementation references" >&2
    sed -n '1,40p' "${output}" >&2
    if (( count > 40 )); then
      echo "FAIL s88-structural-keywords:${label}: truncated; inspect ${output} while this process is running" >&2
    fi
  fi
}

role_words="${tmp_dir}/role-words.txt"
role_abbreviations="${tmp_dir}/role-abbreviations.txt"
lab_site_literals="${tmp_dir}/lab-site-literals.txt"

scan_file \
  "role-words" \
  '"(access|policy|core|upstream-selector|downstream-selector)"|'\''(access|policy|core|upstream-selector|downstream-selector)'\''|\\b(access|policy|core|upstream-selector|downstream-selector)\\b' \
  "${role_words}"

scan_file \
  "role-abbreviations" \
  '"(acc|pol|us|ds)"|'\''(acc|pol|us|ds)'\''|\\b(access-|policy-|core-|upstream-|downstream-|up-|down-|acc-|pol-|us-|ds-)\\b' \
  "${role_abbreviations}"

scan_file \
  "lab-site-literals" \
  'esp0xdeadbeef|s-router|b-router|c-router|lab-host|site-[a-z]' \
  "${lab_site_literals}"

if [[ -s "${role_words}" || -s "${role_abbreviations}" || -s "${lab_site_literals}" ]]; then
  cat >&2 <<'EOF'
FAIL s88-structural-keywords: structural S88 integrity is damaged.
FAIL s88-structural-keywords: role words, role abbreviations, and lab/site
FAIL s88-structural-keywords: literals may appear in include/import routing,
FAIL s88-structural-keywords: but not as local implementation logic. If these
FAIL s88-structural-keywords: strings are needed elsewhere, implement the S88
FAIL s88-structural-keywords: structure and pass parsed values through one
FAIL s88-structural-keywords: linear model instead of parsing names again.
EOF
  exit 1
else
  pass "s88-structural-keywords"
fi
