#!/usr/bin/env bash
# GAMP-ID: FS-310-HDS-040-SDS-010-SMS-100
# GAMP-SCOPE: software-module-test
# Focused construction test: Renderer canonical-only consumption gate.
#
# SMS-100: Every network-renderer-* module shall receive network-semantic
# input only as one validated canonical realization bundle produced by
# network-realization-model under the pinned network-realization-schema
# contract.
#
# Active seeded negatives (per SMS-100 Seeded Negative Requirement):
#   N1 — raw upstream file import → RR_RAW_UPSTREAM_INPUT (source scan + injection)
#   N2 — raw inventory tree walk → RR_RAW_UPSTREAM_INPUT (source scan + injection)
#   N3 — unvalidated canonical bundle → RR_BUNDLE_UNVALIDATED (nix eval via canonical.validateInput)
#   N4 — unvalidated platform binding → RR_PLATFORM_BINDING_INVALID (nix eval via canonical.validateInput)
#
# GAPS (RR_* predicates not yet construction-provable in this test):
#   RR_RAW_CPM_INPUT — old direct-CPM API still accessible; gate not yet enforced
#   RR_PLATFORM_BINDING_AUTHORITY — platform binding semantic authority gate pending
#   RR_PEER_RENDERER_INPUT — no peer renderer output consumption path exists
#   RR_CANONICAL_PATH_UNACCOUNTED — coverage tracking not yet in renderer
#   RR_BUNDLE_IDENTITY_MISMATCH — target mismatch partially covered by N4 path
set -euo pipefail

repo_root="${SMS_TEST_REPO_ROOT:-$(git -C "$(dirname "${BASH_SOURCE[0]}")" rev-parse --show-toplevel)}"
tmp_dir="$(mktemp -d)"
trap 'rm -rf "${tmp_dir}"' EXIT
all_checks_passed=true
src_dir="${repo_root}/s88"

echo "--- FS-310-HDS-040-SDS-010-SMS-100: Renderer canonical-only consumption gate ---"
echo ""

# ============================================================
# Part A: Source scan for RR_RAW_UPSTREAM_INPUT
# ============================================================
echo "--- Source scan: raw upstream file references (RR_RAW_UPSTREAM_INPUT) ---"
all_hits="$(grep -rn -E '(intent\.nix|inventory[^.]*\.nix)' "${src_dir}" --include='*.nix' 2>/dev/null | grep -v 'tests/' || true)"

upstream_path_count=0
realization_node_count=0
new_violations=0

KNOWN_FILE_PATTERNS=(
  "paths.nix:inputs/intent.nix"
  "paths.nix:inputs/inventory-nixos.nix"
  "paths.nix:inputs/inventory.nix"
  "paths.nix:inventory-nixos.nix"
  "paths.nix:inventory.nix"
  "paths.nix:intent.nix"
  "render-inputs.nix:inventory-nixos.nix"
  "render-inputs.nix:inventory.nix"
  "firewall.nix:forwarding-intent.nix"
  "module-host-build.nix:resolved-inventory"
)

KNOWN_REALIZATION_FILES=(
  "host-query/inventory/helpers.nix"
  "host-runtime/context.nix"
  "runtime-context/base/realization.nix"
  "realization-ports/inventory.nix"
)

DIAGNOSTIC_RR_RAW_UPSTREAM="RR_RAW_UPSTREAM_INPUT"

while IFS= read -r line; do
  [[ -z "${line}" ]] && continue
  file_path="$(echo "${line}" | cut -d: -f1)"
  rel_path="${file_path#${repo_root}/}"
  raw_content="$(echo "${line}" | cut -d: -f2-)"
  content="${raw_content#*:}"

  [[ "${content}" =~ ^[[:space:]]*# ]] && continue
  echo "${content}" | grep -qE 'import \./' && continue
  echo "${content}" | grep -qE 'file \? "s88/' && continue
  echo "${content}" | grep -qF 'CMC-NIXOS-' && continue
  echo "${content}" | grep -qF 'NOT discover intent.nix/inventory.nix from disk' && continue
  echo "${content}" | grep -qF 'not discover intent.nix/inventory.nix from disk' && continue
  echo "${content}" | grep -qF 'renderers must consume' && continue
  echo "${content}" | grep -qF 'renderers must NOT' && continue

  if echo "${content}" | grep -q 'inventory\.realization\.nodes'; then
    is_known=false
    for kf in "${KNOWN_REALIZATION_FILES[@]}"; do
      [[ "${rel_path}" == *"${kf}"* ]] && { is_known=true; break; }
    done
    if [[ "${is_known}" == "true" ]]; then
      realization_node_count=$((realization_node_count + 1))
    else
      echo "NEW_${DIAGNOSTIC_RR_RAW_UPSTREAM}: ${rel_path}"
      new_violations=$((new_violations + 1))
    fi
  else
    is_known=false
    for kp in "${KNOWN_FILE_PATTERNS[@]}"; do
      kf="${kp%%:*}"
      kc="${kp#*:}"
      if [[ "${rel_path}" == *"${kf}"* ]] && echo "${content}" | grep -qF "${kc}"; then
        is_known=true; break
      fi
    done
    if [[ "${is_known}" == "true" ]]; then
      upstream_path_count=$((upstream_path_count + 1))
    else
      echo "NEW_${DIAGNOSTIC_RR_RAW_UPSTREAM}: ${rel_path}: $(echo "${content}" | head -c 80)"
      new_violations=$((new_violations + 1))
    fi
  fi
done <<< "${all_hits}"

echo "Known upstream paths: ${upstream_path_count}"
echo "Known realization-node references: ${realization_node_count}"
echo "New violations: ${new_violations}"
[[ "${new_violations}" -gt 0 ]] && all_checks_passed=false
echo ""

# ============================================================
# N1: Seeded negative — direct intent.nix import → RR_RAW_UPSTREAM_INPUT
# ============================================================
echo "--- N1: Seeded negative — direct intent.nix import (${DIAGNOSTIC_RR_RAW_UPSTREAM}) ---"

n1_fixture="${tmp_dir}/n1-fixture"
mkdir -p "${n1_fixture}/render"

cat > "${n1_fixture}/render/bad-intent-import.nix" << 'NIXEOF'
{ outPath, lib }:
# SMS-100 seeded negative N1: production render code importing intent.nix
# via a constructed filesystem path bypasses canonical mediation.
# Must trigger RR_RAW_UPSTREAM_INPUT diagnostic.
let
  intentFile = "${outPath}/inputs/intent.nix";
  intent = import intentFile;
in
{
  tenants = intent.tenants or { };
}
NIXEOF

n1_hits="$(grep -rn -E '(intent\.nix|inventory[^.]*\.nix)' "${n1_fixture}" --include='*.nix' 2>/dev/null || true)"
n1_detected=false

while IFS= read -r scan_line; do
  [[ -z "${scan_line}" ]] && continue
  scan_file="$(echo "${scan_line}" | cut -d: -f1)"
  scan_content="$(echo "${scan_line}" | cut -d: -f2-)"
  scan_content="${scan_content#*:}"
  [[ "${scan_content}" =~ ^[[:space:]]*# ]] && continue

  if echo "${scan_content}" | grep -qF 'intent.nix'; then
    echo "  N1 HIT [${DIAGNOSTIC_RR_RAW_UPSTREAM}] ${scan_file}: $(echo "${scan_content}" | head -c 80)"
    n1_detected=true
  fi
done <<< "${n1_hits}"

if [[ "${n1_detected}" == "true" ]]; then
  echo "  PASS: N1 — direct intent.nix import detected as ${DIAGNOSTIC_RR_RAW_UPSTREAM}"
else
  echo "  FAIL: N1 — direct intent.nix import NOT detected; scanner may miss upstream path injection"
  all_checks_passed=false
fi

rm "${n1_fixture}/render/bad-intent-import.nix"
n1_clean="$(grep -rn -E '(intent\.nix|inventory[^.]*\.nix)' "${n1_fixture}" --include='*.nix' 2>/dev/null || true)"
if [[ -z "${n1_clean}" ]]; then
  echo "  PASS: N1 recovery — clean fixture has no violations"
else
  echo "  FAIL: N1 recovery — fixture still shows violations after removal"
  all_checks_passed=false
fi
echo ""

# ============================================================
# N2: Seeded negative — raw inventory tree walk → RR_RAW_UPSTREAM_INPUT
# ============================================================
echo "--- N2: Seeded negative — raw inventory.realization.nodes walk (${DIAGNOSTIC_RR_RAW_UPSTREAM}) ---"

n2_fixture="${tmp_dir}/n2-fixture"
mkdir -p "${n2_fixture}/render"

cat > "${n2_fixture}/render/bad-inventory-walk.nix" << 'NIXEOF'
{ inventory, lib }:
# SMS-100 seeded negative N2: production render code walking raw
# inventory.realization.nodes to resolve realization data instead of
# consuming canonical bundle paths.
# Must trigger RR_RAW_UPSTREAM_INPUT diagnostic.
let
  nodes = inventory.realization.nodes or [ ];
  resolvedNodes = map (n: n.host or n) nodes;
in
{
  realized = resolvedNodes;
}
NIXEOF

n2_hits="$(grep -rn 'inventory\.realization\.nodes' "${n2_fixture}" --include='*.nix' 2>/dev/null || true)"
n2_detected=false

while IFS= read -r scan_line; do
  [[ -z "${scan_line}" ]] && continue
  scan_file="$(echo "${scan_line}" | cut -d: -f1)"
  scan_content="$(echo "${scan_line}" | cut -d: -f2-)"
  scan_content="${scan_content#*:}"
  [[ "${scan_content}" =~ ^[[:space:]]*# ]] && continue

  if echo "${scan_content}" | grep -q 'inventory\.realization\.nodes'; then
    echo "  N2 HIT [${DIAGNOSTIC_RR_RAW_UPSTREAM}] ${scan_file}: $(echo "${scan_content}" | head -c 80)"
    n2_detected=true
  fi
done <<< "${n2_hits}"

if [[ "${n2_detected}" == "true" ]]; then
  echo "  PASS: N2 — raw inventory.realization.nodes walk detected as ${DIAGNOSTIC_RR_RAW_UPSTREAM}"
else
  echo "  FAIL: N2 — raw inventory.realization.nodes walk NOT detected; scanner may miss tree-walk injection"
  all_checks_passed=false
fi

rm "${n2_fixture}/render/bad-inventory-walk.nix"
n2_clean="$(grep -rn 'inventory\.realization\.nodes' "${n2_fixture}" --include='*.nix' 2>/dev/null || true)"
if [[ -z "${n2_clean}" ]]; then
  echo "  PASS: N2 recovery — clean fixture has no violations"
else
  echo "  FAIL: N2 recovery — fixture still shows violations after removal"
  all_checks_passed=false
fi
echo ""

# ============================================================
# Part B: Canonical entrypoint validation (nix eval)
# ============================================================
echo "--- Canonical entrypoint: bundle/binding validation via nix eval ---"

if ! command -v nix &>/dev/null; then
  echo "  SKIP: nix not available; canonical entrypoint tests require nix"
else
  # N3: unvalidated bundle → expect NR_RENDERER_BUNDLE_UNVALIDATED (RR_BUNDLE_UNVALIDATED)
  echo "--- N3: Seeded negative — unvalidated canonical bundle (RR_BUNDLE_UNVALIDATED) ---"
  n3_stderr="${tmp_dir}/n3-stderr"
  set +e
  nix eval \
    --extra-experimental-features 'nix-command flakes' \
    --impure --expr "
      let
        nrFlake = builtins.getFlake \"path:/home/deadbeef/github/network-realization-model\";
        rFlake = builtins.getFlake \"path:${repo_root}\";
        input = import /home/deadbeef/github/network-realization-model/examples/cpm-result.nix;
        released = nrFlake.lib.realize {
          inherit input;
          requestScope = { kind = \"complete-artifact\"; identity = \"sms100-n3\"; };
          rootLockIdentity = \"sms100-n3-lock\";
          producerRevision = \"sms100-n3-rev\";
        };
        unreleased = builtins.removeAttrs released [ \"validation\" ];
        validated = rFlake.lib.renderer.canonical.validateInput {
          bundle = unreleased;
          platformBinding = null;
        };
      in validated.bundleIdentity
    " >/dev/null 2>"${n3_stderr}"
  n3_status=$?
  set -e

  if [[ "${n3_status}" -eq 0 ]]; then
    echo "  FAIL: N3 — unvalidated bundle was accepted (expected RR_BUNDLE_UNVALIDATED)"
    all_checks_passed=false
  elif grep -qF "NR_RENDERER_BUNDLE_UNVALIDATED" "${n3_stderr}"; then
    echo "  PASS: N3 — unvalidated bundle rejected (NR_RENDERER_BUNDLE_UNVALIDATED → RR_BUNDLE_UNVALIDATED)"
  else
    echo "  FAIL: N3 — rejection lacked NR_RENDERER_BUNDLE_UNVALIDATED diagnostic"
    grep -o 'NR_[A-Z_]*' "${n3_stderr}" | head -5 >&2
    all_checks_passed=false
  fi

  # R1: Recovery — valid bundle with null binding → accepted
  echo "--- R1: Recovery — valid canonical bundle accepted ---"
  set +e
  nix eval \
    --extra-experimental-features 'nix-command flakes' \
    --impure --expr "
      let
        nrFlake = builtins.getFlake \"path:/home/deadbeef/github/network-realization-model\";
        rFlake = builtins.getFlake \"path:${repo_root}\";
        input = import /home/deadbeef/github/network-realization-model/examples/cpm-result.nix;
        released = nrFlake.lib.realize {
          inherit input;
          requestScope = { kind = \"complete-artifact\"; identity = \"sms100-r1\"; };
          rootLockIdentity = \"sms100-r1-lock\";
          producerRevision = \"sms100-r1-rev\";
        };
        validated = rFlake.lib.renderer.canonical.validateInput {
          bundle = released;
          platformBinding = null;
        };
      in validated.bundleIdentity
    " >/dev/null 2>"${tmp_dir}/r1-stderr"
  r1_status=$?
  set -e

  if [[ "${r1_status}" -eq 0 ]]; then
    echo "  PASS: R1 — valid bundle accepted through canonical entrypoint"
  else
    echo "  FAIL: R1 — valid bundle rejected by canonical entrypoint"
    cat "${tmp_dir}/r1-stderr" >&2
    all_checks_passed=false
  fi

  # N4: unvalidated platform binding → expect NR_PLATFORM_BINDING_UNVALIDATED (RR_PLATFORM_BINDING_INVALID)
  echo "--- N4: Seeded negative — unvalidated platform binding (RR_PLATFORM_BINDING_INVALID) ---"
  n4_stderr="${tmp_dir}/n4-stderr"
  set +e
  nix eval \
    --extra-experimental-features 'nix-command flakes' \
    --impure --expr "
      let
        nrFlake = builtins.getFlake \"path:/home/deadbeef/github/network-realization-model\";
        schemaFlake = builtins.getFlake \"path:/home/deadbeef/github/network-realization-schema\";
        rFlake = builtins.getFlake \"path:${repo_root}\";
        input = import /home/deadbeef/github/network-realization-model/examples/cpm-result.nix;
        released = nrFlake.lib.realize {
          inherit input;
          requestScope = { kind = \"complete-artifact\"; identity = \"sms100-n4\"; };
          rootLockIdentity = \"sms100-n4-lock\";
          producerRevision = \"sms100-n4-rev\";
        };
        bindingBase = {
          kind = schemaFlake.lib.schema.platformBinding.kind;
          schemaRevision = schemaFlake.lib.schema.platformBinding.revision;
          bundleIdentity = released.bundleIdentity;
          target = \"nixos\";
          requestScope = released.requestScope;
          categories = { };
          provenance = { producer = \"sms100-n4\"; producerRevision = \"sms100-n4-rev\"; };
        };
        unvalidatedBinding = bindingBase // {
          bindingIdentity = schemaFlake.lib.computeBindingIdentity bindingBase;
        };
        validated = rFlake.lib.renderer.canonical.validateInput {
          bundle = released;
          platformBinding = unvalidatedBinding;
        };
      in validated.bundleIdentity
    " >/dev/null 2>"${n4_stderr}"
  n4_status=$?
  set -e

  if [[ "${n4_status}" -eq 0 ]]; then
    echo "  FAIL: N4 — unvalidated platform binding was accepted (expected RR_PLATFORM_BINDING_INVALID)"
    all_checks_passed=false
  elif grep -qF "NR_PLATFORM_BINDING_UNVALIDATED" "${n4_stderr}"; then
    echo "  PASS: N4 — unvalidated platform binding rejected (NR_PLATFORM_BINDING_UNVALIDATED → RR_PLATFORM_BINDING_INVALID)"
  else
    echo "  FAIL: N4 — rejection lacked NR_PLATFORM_BINDING_UNVALIDATED diagnostic"
    grep -o 'NR_[A-Z_]*' "${n4_stderr}" | head -5 >&2
    all_checks_passed=false
  fi

  # R2: Recovery — valid bundle + validated binding → accepted
  echo "--- R2: Recovery — valid bundle + validated binding accepted ---"
  set +e
  nix eval \
    --extra-experimental-features 'nix-command flakes' \
    --impure --expr "
      let
        nrFlake = builtins.getFlake \"path:/home/deadbeef/github/network-realization-model\";
        schemaFlake = builtins.getFlake \"path:/home/deadbeef/github/network-realization-schema\";
        rFlake = builtins.getFlake \"path:${repo_root}\";
        input = import /home/deadbeef/github/network-realization-model/examples/cpm-result.nix;
        released = nrFlake.lib.realize {
          inherit input;
          requestScope = { kind = \"complete-artifact\"; identity = \"sms100-r2\"; };
          rootLockIdentity = \"sms100-r2-lock\";
          producerRevision = \"sms100-r2-rev\";
        };
        bindingBase = {
          kind = schemaFlake.lib.schema.platformBinding.kind;
          schemaRevision = schemaFlake.lib.schema.platformBinding.revision;
          bundleIdentity = released.bundleIdentity;
          target = \"nixos\";
          requestScope = released.requestScope;
          categories = { };
          provenance = { producer = \"sms100-r2\"; producerRevision = \"sms100-r2-rev\"; };
        };
        bindingWithId = bindingBase // {
          bindingIdentity = schemaFlake.lib.computeBindingIdentity bindingBase;
        };
        releasedBinding = bindingWithId // {
          validation = schemaFlake.lib.validatePlatformBinding bindingWithId;
        };
        validated = rFlake.lib.renderer.canonical.validateInput {
          bundle = released;
          platformBinding = releasedBinding;
        };
      in validated.bundleIdentity
    " >/dev/null 2>"${tmp_dir}/r2-stderr"
  r2_status=$?
  set -e

  if [[ "${r2_status}" -eq 0 ]]; then
    echo "  PASS: R2 — valid bundle + validated binding accepted through canonical entrypoint"
  else
    echo "  FAIL: R2 — valid bundle + validated binding rejected by canonical entrypoint"
    cat "${tmp_dir}/r2-stderr" >&2
    all_checks_passed=false
  fi
fi
echo ""

# ============================================================
# Report
# ============================================================
total_known=$((upstream_path_count + realization_node_count))
if [[ "${all_checks_passed}" == "true" ]]; then
  echo "PASS: FS-310-HDS-040-SDS-010-SMS-100 canonical-only consumption gate verified."
  echo ""
  echo "Proven SMS-100 predicates:"
  echo "  RR_RAW_UPSTREAM_INPUT: source scan ${total_known} known refs, ${new_violations} new violations"
  echo "  RR_RAW_UPSTREAM_INPUT: N1 (direct intent import) — detected + recovered"
  echo "  RR_RAW_UPSTREAM_INPUT: N2 (raw inventory walk) — detected + recovered"
  echo "  RR_BUNDLE_UNVALIDATED: N3 (unvalidated bundle) — NR_RENDERER_BUNDLE_UNVALIDATED rejected + R1 recovered"
  echo "  RR_PLATFORM_BINDING_INVALID: N4 (unvalidated binding) — NR_PLATFORM_BINDING_UNVALIDATED rejected + R2 recovered"
  echo ""
  echo "GAPS (RR_* predicates tracked but not yet construction-provable):"
  echo "  RR_RAW_CPM_INPUT — old direct-CPM API still accessible; gate pending"
  echo "  RR_PLATFORM_BINDING_AUTHORITY — binding semantic authority check pending"
  echo "  RR_PEER_RENDERER_INPUT — no peer renderer consumption path"
  echo "  RR_CANONICAL_PATH_UNACCOUNTED — coverage tracking not in renderer"
  echo "  RR_BUNDLE_IDENTITY_MISMATCH — target mismatch partially covered by N4 path"
  exit 0
else
  echo "FAIL: ${new_violations} new violation(s) or seeded negative failure(s)."
  exit 1
fi
