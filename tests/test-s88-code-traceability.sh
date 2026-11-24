#!/usr/bin/env bash
# GAMP-SCOPE: repository architecture conformance guard; not SMT acceptance
# evidence -- no SMS row exists yet (see TRACE NOTE).
#
# TRACE NOTE
# ----------
# This file carries no `# GAMP-ID:` header on purpose. `GAMP/methodology/
# trace-chain-ids.md` requires a test's header to be a FULL trace chain ending
# in `SMS-NNN`, and the layer rule is "no CMC/test without SMS". No SMS row owns
# this predicate yet, so citing the SDS (`FS-310-HDS-010-SDS-010`) or inventing
# an SMS number would be false traceability. The precedent in this repository is
# `tests/test-no-private-mirror-reference.sh`, which is a repository guard with a
# `GAMP-SCOPE` and no ID.
#
# Recorded gap, to be closed in the owning GAMP layer: the SDS that owns the S88
#   layout (README.md -> Spec Chain, `FS-310-HDS-010-SDS-010`).
#
# CODE TRACEABILITY: a source file the trace does not list is not traceable CODE.
#
# READ THIS FIRST
# ---------------
# This test enforces a rule the repository states about itself, in
# `s88/ControlModule/render/container-networks/policy-routing/TRACE.md`:
#
#   "This file is the repo-local CODE trace for the NixOS policy-routing
#    ControlModule package. It explains why each source file exists, which S88
#    layer owns it, and which controlled construction specification it implements."
#
#   "Dead-code rule: a Nix policy-routing source file that is not listed here is
#    not traceable CODE. It must either be added here with a specific CMC function
#    and focused test evidence, or removed."
#
# That paragraph is the owner of this rule. This test does not restate it; it
# checks it. If the rule should be different, change TRACE.md and the owning
# GAMP layer -- not this script.
#
# The S88 LAYER column is also checked for coherence with the level hierarchy
# described by the workspace ISA-88 architecture note (not in this repository,
# which is why this test can only check ORDER, not meaning): a trace row that
# lists several levels must list them highest authority first. That is the only
# property of the level vocabulary that a markdown column can be held to.
#
# STATUS: EXPECTED RED. T1 currently reports five unlisted source files.
# Do not make this pass by deleting the files or by deleting this test; AGENTS.md
# "Fixing rules" rules 1 and 2. TRACE.md names both permitted resolutions.
#
# Evidence boundary: construction. Static file reads only. No evaluation, no
# build, no lab, no network.
set -euo pipefail

repo_root="${SMS_TEST_REPO_ROOT:-$(git -C "$(dirname "${BASH_SOURCE[0]}")" rev-parse --show-toplevel)}"
source "${repo_root}/tests/lib/direct-test-guard.sh" 2>/dev/null || true

trace_dir="s88/ControlModule/render/container-networks/policy-routing"
trace_file="${repo_root}/${trace_dir}/TRACE.md"

# ---------------------------------------------------------------------------
# level_rank <Level> -- position in the hierarchy, 1 = highest authority.
# level_order_in <text> -- the levels named in <text>, in TEXT order.
#
# Rank order must follow the text, not the hierarchy. Building the list by
# iterating the hierarchy makes it ascending by construction, so the check can
# never fire -- which is what the seeded negative caught before it shipped.
# ---------------------------------------------------------------------------
level_rank() {
  case "$1" in
    Enterprise) echo 1 ;;
    Site) echo 2 ;;
    Area) echo 3 ;;
    ProcessCell) echo 4 ;;
    Unit) echo 5 ;;
    EquipmentModule) echo 6 ;;
    ControlModule) echo 7 ;;
    *) echo 99 ;;
  esac
}

level_order_in() {
  local text="$1" level offset
  for level in Enterprise Site Area ProcessCell Unit EquipmentModule ControlModule; do
    # `|| true`: under `set -o pipefail` a grep that finds nothing fails the
    # whole pipeline, and a failing command substitution aborts this function.
    # Two separate `set -e` traps had to be removed before the seeded negative
    # went green, and both were silently disabling the check.
    # Case-SENSITIVE on purpose: the column writes levels as proper nouns.
    # A case-insensitive match reads the prose in "site destination extraction"
    # as the Site level, which reports an inversion that is not there.
    offset="$(printf '%s' "${text}" | grep -boE "(^|[^A-Za-z])${level}([^A-Za-z]|$)" | head -1 | cut -d: -f1 || true)"
    if [[ -n "${offset}" ]]; then
      printf '%s\t%s\n' "${offset}" "${level}"
    fi
  done | sort -n | cut -f2
}

issues=0

report_issue() {
  local id="$1" finding="$2" why="$3" read="$4"
  issues=$((issues + 1))
  {
    echo "ISSUE ${id}: ${finding}"
    echo "  why:  ${why}"
    echo "  read: ${read}"
    echo
  } >&2
}

echo "--- S88-CODE-TRACE: policy-routing CODE traceability ---"
echo ""

if [[ ! -f "${trace_file}" ]]; then
  report_issue "T0" "${trace_dir}/TRACE.md does not exist" \
    "without it there is no declared CODE surface for the policy-routing package,
       and the dead-code rule above has nothing to bind to" \
    "the workspace ISA-88 architecture note, and FS-310-HDS-010-SDS-010 in
       README.md -> Spec Chain (S88 layout / interface architecture)"
  echo "FAIL S88-CODE-TRACE (code traceability): trace file missing" >&2
  exit 1
fi

# ---------------------------------------------------------------------------
# T1 -- every source file in the CODE surface is listed.
#
# A file that exists but is not listed has no declared S88 layer and no CMC
# function, so it is code nobody owns. It is also the most likely home for the
# next derivation shortcut, because no trace row can disagree with it.
# ---------------------------------------------------------------------------
unlisted=()
while IFS= read -r file; do
  [[ -n "${file}" ]] || continue
  rel="${file#"${repo_root}/"}"
  grep -qF "${rel}" "${trace_file}" || unlisted+=("${rel}")
done < <(find "${repo_root}/${trace_dir}" -maxdepth 1 -type f -name '*.nix' | LC_ALL=C sort)

if ((${#unlisted[@]} > 0)); then
  issues=$((issues + 1))
  {
    echo "ISSUE T1: ${#unlisted[@]} source file(s) in ${trace_dir}/ are not listed in TRACE.md"
    for file in "${unlisted[@]}"; do
      echo "    ${file}"
    done
    echo "  why:  TRACE.md's own dead-code rule makes an unlisted file untraceable: it has"
    echo "        no declared S88 layer and no CMC function, so no trace row can be"
    echo "        checked against it. These files are therefore where a behaviour can"
    echo "        appear without a specification."
    echo "  read: ${trace_dir}/TRACE.md -- the 'Dead-code rule' paragraph, then"
    echo "        FS-310-HDS-010-SDS-010 in README.md -> Spec Chain."
    echo
  } >&2
else
  echo "PASS T1: every policy-routing source file is listed in TRACE.md"
fi

# ---------------------------------------------------------------------------
# T2 -- every listed path exists, and T3 -- every row is well formed.
#
# A dangling row is the mirror defect: the trace claims a CODE surface that is
# gone, so a reader following it lands nowhere.
# ---------------------------------------------------------------------------
dangling=()
malformed=()
row_count=0

while IFS= read -r row; do
  [[ -n "${row}" ]] || continue
  row_count=$((row_count + 1))

  IFS='|' read -r _ path layer cmc _rest <<<"${row}"

  path="$(sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' -e 's/^`//' -e 's/`$//' <<<"${path}")"
  layer="$(sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' <<<"${layer}")"
  cmc="$(sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' <<<"${cmc}")"

  [[ -n "${path}" ]] && [[ ! -e "${repo_root}/${path}" ]] && dangling+=("${path}")

  if [[ -z "${layer}" ]] || [[ -z "${cmc}" ]]; then
    malformed+=("${path:-<row ${row_count}>}")
    continue
  fi
  grep -qE "CMC-FUNC-" <<<"${cmc}" || malformed+=("${path} (no CMC-FUNC id)")

  # -------------------------------------------------------------------
  # T4 -- level order in the S88 LAYER column.
  #
  # The column names levels from highest (broadest authority) to lowest. A row
  # that lists them in the other order describes an inversion, whatever the code
  # does. Only ORDER is checked here; what each level means is owned by the
  # workspace note.
  # -------------------------------------------------------------------
  ranks=()
  mapfile -t ordered_levels < <(level_order_in "${layer}")
  if ((${#ordered_levels[@]} > 1)); then
    previous=0
    for level in "${ordered_levels[@]}"; do
      rank="$(level_rank "${level}")"
      if ((rank < previous)); then
        malformed+=("${path} (S88 LAYER lists ${level} after a narrower level: ${layer})")
        break
      fi
      previous="${rank}"
    done
  fi
done < <(grep -E "^\|[[:space:]]*\`?${trace_dir}/" "${trace_file}" || true)

if ((${#dangling[@]} > 0)); then
  issues=$((issues + 1))
  {
    echo "ISSUE T2: ${#dangling[@]} TRACE.md row(s) name a file that does not exist"
    for path in "${dangling[@]}"; do echo "    ${path}"; done
    echo "  why:  the row is the only statement of that file's S88 layer and CMC"
    echo "        function. Once the file is gone the row documents a responsibility"
    echo "        the repository no longer discharges, and nothing fails."
    echo "  read: ${trace_dir}/TRACE.md -- the 'Dead-code rule' paragraph"
    echo
  } >&2
else
  echo "PASS T2: every TRACE.md row names an existing file"
fi

if ((${#malformed[@]} > 0)); then
  issues=$((issues + 1))
  {
    echo "ISSUE T3/T4: ${#malformed[@]} TRACE.md row(s) are incomplete or self-contradictory"
    for path in "${malformed[@]}"; do echo "    ${path}"; done
    echo "  why:  a row with no CMC function cannot be checked against a specification,"
    echo "        and a row whose S88 LAYER lists levels out of order describes an"
    echo "        inversion that the hierarchy does not permit."
    echo "  read: ${trace_dir}/TRACE.md, then the workspace ISA-88 architecture note"
    echo "        (not in this repository) for the level order the column must follow."
    echo
  } >&2
else
  echo "PASS T3/T4: every TRACE.md row carries a CMC function and an ordered S88 layer (${row_count} rows)"
fi

# ---------------------------------------------------------------------------
# T5 -- every `# GAMP-ID:` header in tests/ is a valid trace chain.
#
# The owner of this rule is the GAMP methodology note on trace-chain IDs (in the
# GAMP-for-agents methodology tree, not this repository). Two of its rules are
# mechanical:
#
#   - a test header must be a FULL chain ending in `SMS-NNN`
#     (`# GAMP-ID: FS-010-HDS-010-SDS-010-SMS-010`), so a header that stops at
#     SDS is not an ID;
#   - IDs are numeric handles, so a header that carries domain words inside the
#     token is not an ID either.
#
# The companion rule -- "no CMC/test without SMS" -- is why a test with no SMS
# row carries no `# GAMP-ID:` at all instead of citing the SDS it belongs to.
#
# Out of scope here: whether a well-formed ID resolves to a row in the canonical
# SMS tree. That tree is not in this repository and validating it is the GAMP
# tree's job, not a renderer test's.
# ---------------------------------------------------------------------------
trace_id_re='^FS-[0-9]+-HDS-[0-9]+-SDS-[0-9]+-SMS-[0-9]+$'
bad_ids=()
while IFS= read -r line; do
  [[ -n "${line}" ]] || continue
  file="${line%%:*}"
  rest="${line#*:}"
  content="${rest#*:}"
  id="${content#\# GAMP-ID: }"
  for token in ${id}; do
    core="$(sed -E 's/-CMC-[0-9]+$//' <<<"${token}")"
    [[ "${core}" =~ ${trace_id_re} ]] || bad_ids+=("${file#"${repo_root}/"}: '${token}'")
  done
done < <(grep -rn "^# GAMP-ID:" "${repo_root}/tests" --include='*.sh' --include='*.py' 2>/dev/null || true)

if ((${#bad_ids[@]} > 0)); then
  issues=$((issues + 1))
  {
    echo "ISSUE T5: ${#bad_ids[@]} trace-chain token(s) in test headers are not full SMS chains"
    for entry in "${bad_ids[@]}"; do echo "    ${entry}"; done
    echo "  why:  GAMP trace-chain IDs are numeric handles with a fixed shape, and a"
    echo "        test header must end in SMS because the module contract is what a"
    echo "        test is evidence for. A header that stops at SDS, or carries words"
    echo "        inside the token, cannot be resolved to a row, so the evidence it"
    echo "        claims has no owner."
    echo "  read: the GAMP methodology note on trace-chain IDs (format, the 'headers'"
    echo "        example, and 'do not put domain words inside ID tokens'). Then decide,"
    echo "        for each hit, either the SMS row that owns it or -- when no SMS exists"
    echo "        -- a GAMP-SCOPE header with no ID at all."
    echo
  } >&2
else
  echo "PASS T5: every test GAMP-ID is a full trace chain ending in SMS"
fi


seeded_root="$(mktemp -d)"
trap 'rm -rf "${seeded_root}"' EXIT
mkdir -p "${seeded_root}/${trace_dir}"
printf '{ lib }: { }\n' >"${seeded_root}/${trace_dir}/present.nix"

cat >"${seeded_root}/${trace_dir}/TRACE.md" <<'MD'
| CODE SURFACE | S88 LAYER | SPEC TRACE | WHY THIS FUNCTION EXISTS |
| --- | --- | --- | --- |
| `s88/ControlModule/render/container-networks/policy-routing/present.nix` | ControlModule -> Unit | `CMC-FUNC-SEED-001` | seeded: levels listed lowest-first |
| `s88/ControlModule/render/container-networks/policy-routing/absent.nix` | Unit -> ControlModule | `CMC-FUNC-SEED-002` | seeded: dangling path |
MD

# seeded negative for T5: one SDS-level header, one word-bearing header.
printf '#!/usr/bin/env bash\n# GAMP-ID: FS-010-HDS-010-SDS-010\n' >"${seeded_root}/seeded-id.sh"
printf '#!/usr/bin/env bash\n# GAMP-ID: FS-010-HDS-010-SDS-010-SMS-010 (seeded words)\n' >"${seeded_root}/seeded-words.sh"

seeded_dangling=0
seeded_disorder=0
while IFS= read -r row; do
  [[ -n "${row}" ]] || continue
  IFS='|' read -r _ path layer _cmc _rest <<<"${row}"
  path="$(sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' -e 's/^`//' -e 's/`$//' <<<"${path}")"
  layer="$(sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' <<<"${layer}")"
  [[ -n "${path}" ]] && [[ ! -e "${seeded_root}/${path}" ]] && seeded_dangling=$((seeded_dangling + 1))

  mapfile -t ordered_levels < <(level_order_in "${layer}")
  if ((${#ordered_levels[@]} > 1)); then
    previous=0
    for level in "${ordered_levels[@]}"; do
      rank="$(level_rank "${level}")"
      if ((rank < previous)); then seeded_disorder=$((seeded_disorder + 1)); break; fi
      previous="${rank}"
    done
  fi
done < <(grep -E "^\|[[:space:]]*\`?${trace_dir}/" "${seeded_root}/${trace_dir}/TRACE.md" || true)

seeded_bad_ids=0
while IFS= read -r line; do
  [[ -n "${line}" ]] || continue
  rest="${line#*:}"
  id="${rest#\# GAMP-ID: }"
  for token in ${id}; do
    core="$(sed -E 's/-CMC-[0-9]+$//' <<<"${token}")"
    [[ "${core}" =~ ${trace_id_re} ]] || seeded_bad_ids=$((seeded_bad_ids + 1))
  done
done < <(grep -rn "^# GAMP-ID:" "${seeded_root}" --include='*.sh' 2>/dev/null || true)

if ((seeded_dangling < 1 || seeded_disorder < 1 || seeded_bad_ids < 2)); then
  report_issue "T-SEED" "the trace-table checks did not detect the seeded defects" \
    "expected >=1 dangling row, >=1 out-of-order S88 LAYER and >=2 bad trace IDs, got
       dangling=${seeded_dangling} disorder=${seeded_disorder} bad_ids=${seeded_bad_ids}.
       Every PASS this test printed is not evidence" \
    "tests/test-s88-code-traceability.sh -- the row loop, the T4 rank comparison and the T5 token check"
else
  echo "PASS T-SEED: parser found the seeded dangling row, level inversion and bad trace IDs"
fi

echo ""
if ((issues > 0)); then
  echo "FAIL S88-CODE-TRACE (code traceability): ${issues} issue(s)." >&2
  echo "  Read ${trace_dir}/TRACE.md before adding or removing a source file." >&2
  exit 1
fi

echo "PASS S88-CODE-TRACE (code traceability)"
exit 0
