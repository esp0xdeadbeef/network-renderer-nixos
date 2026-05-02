#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
normal_limit="${NIX_LOC_NORMAL_LIMIT:-150}"
review_limit="${NIX_LOC_REVIEW_LIMIT:-250}"
hard_limit="${NIX_LOC_HARD_LIMIT:-500}"
today="${NIX_LOC_TODAY:-$(date -u +%F)}"

mapfile -t sized < <(
  cd "$repo_root"
  git ls-files -z '*.nix' \
    | while IFS= read -r -d '' path; do
        [[ -f "$path" ]] && printf '%s\0' "$path"
      done \
    | xargs -0 -r wc -l \
    | awk -v normal="$normal_limit" -v review="$review_limit" '
      $2 != "total" && $2 !~ /(^|\/)(tests?|fixtures)\// && $1 > normal {
        layer = "Unknown"
        if ($2 ~ /^s88\/Site\//) layer = "Site"
        else if ($2 ~ /^s88\/Unit\//) layer = "Unit"
        else if ($2 ~ /^s88\/EquipmentModule\//) layer = "EquipmentModule"
        else if ($2 ~ /^s88\/ControlModule\//) layer = "ControlModule"
        else if ($2 ~ /^s88\/Enterprise\//) layer = "Enterprise"
        band = "150-250 acceptable when single-responsibility"
        if ($1 > review) band = "250+ justify-or-split"
        print $1 " " layer " " band " " $2
      }' \
    | sort -nr
)

if ((${#sized[@]} > 0)); then
  printf 'Layered Nix LOC report outside tests/fixtures:\n' >&2
  printf '  <=%s: normal target\n' "$normal_limit" >&2
  printf '  %s-%s: acceptable if single responsibility and easy to scan\n' "$((normal_limit + 1))" "$review_limit" >&2
  printf '  >%s: must justify why splitting would reduce clarity\n' "$review_limit" >&2
  printf '  >%s: hard fail unless generated/declarative/table-like\n' "$hard_limit" >&2
  printf '\nReview rule for every >%s LOC file:\n' "$review_limit" >&2
  printf '  1. Identify the single responsibility in one sentence.\n' >&2
  printf '  2. If that sentence contains "and", split.\n' >&2
  printf '  3. If the file mixes lookup, mapping, validation, and render, split.\n' >&2
  printf '  4. If kept, add a short justification to regression.md.\n' >&2
  printf '  5. Re-run the LOC and boundary tests.\n\n' >&2
  printf 'A >%s LOC regression.md entry must state ACCEPTED OVER-LIMIT or date-bound TEMPORARY OVER-LIMIT until YYYY-MM-DD.\n\n' "$review_limit" >&2
  printf '%s\n' "${sized[@]}" >&2
fi

mapfile -t oversized < <(printf '%s\n' "${sized[@]:-}" | awk -v hard="$hard_limit" '$1 > hard')
mapfile -t needs_justification < <(printf '%s\n' "${sized[@]:-}" | awk -v review="$review_limit" '$1 > review { print $NF }')
missing_justifications=()

for path in "${needs_justification[@]}"; do
  if ! awk -v path="$path" '
    index($0, path) {
      block = $0
      for (i = 0; i < 4; i++) {
        if ((getline line) <= 0) {
          break
        }
        if (line ~ /^- `/) {
          break
        }
        block = block "\n" line
      }
      if (block ~ /ACCEPTED OVER-LIMIT/) {
        found = 1
      } else if (match(block, /TEMPORARY OVER-LIMIT until ([0-9]{4}-[0-9]{2}-[0-9]{2})/, date)) {
        if (date[1] >= today) {
          found = 1
        }
      }
    }
    END { exit(found ? 0 : 1) }
  ' today="$today" "$repo_root/regression.md"; then
    missing_justifications+=("$path")
  fi
done

if ((${#missing_justifications[@]} > 0)); then
  printf '\n>250 LOC files missing accepted status or unexpired temporary date in regression.md:\n' >&2
  printf '%s\n' "${missing_justifications[@]}" >&2
  exit 1
fi

if ((${#oversized[@]} > 0)); then
  printf '\nHard LOC violations. Split by responsibility, not by line count alone:\n' >&2
  printf '%s\n' "${oversized[@]}" >&2
  exit 1
fi
