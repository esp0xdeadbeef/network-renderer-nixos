#!/usr/bin/env bash
# GAMP-ID: FS-320-HDS-050-SDS-010-SMS-010
# GAMP-SCOPE: software-module-test
#
# Focused construction test for the attachment surface binding module
# (SMS-010). Expected state: FAILING. The module does not exist yet; each
# predicate below names the behaviour the module must implement and the
# diagnostic it must emit, so a solution can be proven against it without the
# solution being invented here.
#
# Predicates, from the SMS:
#   1. surface record validation — exactly one surfaceClass
#      (physical | external-bridge | internal-bridge), exactly one surfaceRef,
#      one surfaceRefSource.
#   2. lookup-only binding — the named surfaceRef is bound as given; no
#      candidate enumeration, no rename to fit, no class fallback.
#   3. class-expressibility limitation — a target that cannot express the
#      declared class yields a limitation record, not a binding.
#   4. no substitution — a binding that uses any surface other than the named
#      one fails closed.
#   5. no runtime discovery — the module consumes no interface enumeration and
#      no ip-link output.
#   6. legal islands — a site with no physical attachment, an external bridge
#      with no members, and an ungrounded internal bridge are all accepted
#      without a defect diagnostic.
set -euo pipefail

repo_root="${SMS_TEST_REPO_ROOT:-$(git -C "$(dirname "${BASH_SOURCE[0]}")" rev-parse --show-toplevel)}"
source "${repo_root}/tests/lib/test-common.sh"

trace_id="${SMS_TEST_TRACE_ID:-FS-320-HDS-050-SDS-010-SMS-010}"
tmp_dir="$(mktemp -d)"
trap 'rm -rf "${tmp_dir}"' EXIT

result_json="${tmp_dir}/${trace_id}.json"
stderr_file="${tmp_dir}/${trace_id}.stderr"

all_checks_passed=true
record_pass() { echo "PASS ${trace_id}: $1"; }
record_fail() { echo "FAIL ${trace_id}: $1" >&2; all_checks_passed=false; }

nix_eval_json_or_fail \
  "${trace_id} attachment surface binding" \
  "${result_json}" \
  "${stderr_file}" \
  env REPO_ROOT="${repo_root}" \
    nix eval \
      --extra-experimental-features 'nix-command flakes' \
      --impure --json \
      --file "${repo_root}/tests/nix/fs320-hds050-sds010-sms010-attachment-surface-binding.nix"

module_file="${repo_root}/s88/Unit/physical/attachment-surface.nix"
binding_module_file="${repo_root}/s88/Unit/physical/attachment-surface/binding.nix"

if [[ ! -f "${module_file}" && ! -f "${binding_module_file}" ]]; then
  record_fail "attachment surface binding module is absent: neither ${module_file#"${repo_root}/"} nor ${binding_module_file#"${repo_root}/"} exists"
else
  record_pass "attachment surface binding module is present"
fi

for predicate in \
  surface_record_validation \
  lookup_only_binding \
  class_limitation_reporting \
  substitution_rejection \
  no_runtime_discovery \
  legal_island_acceptance
do
  if [[ "$(jq -r --arg p "${predicate}" '.checks[$p] // false' "${result_json}")" == "true" ]]; then
    record_pass "predicate ${predicate}"
  else
    record_fail "predicate ${predicate}"
  fi
done

for negative in \
  substituted_surface_rejected \
  collapsed_surface_record_rejected
do
  if [[ "$(jq -r --arg n "${negative}" '.seededNegatives[$n] // false' "${result_json}")" == "true" ]]; then
    record_pass "seeded negative ${negative} active"
  else
    record_fail "seeded negative ${negative} is not active"
  fi
done

for acceptance in \
  no_physical_attachment_accepted \
  ungrounded_island_accepted
do
  if [[ "$(jq -r --arg a "${acceptance}" '.acceptance[$a] // false' "${result_json}")" == "true" ]]; then
    record_pass "acceptance case ${acceptance}"
  else
    record_fail "acceptance case ${acceptance}"
  fi
done

if ${all_checks_passed}; then
  echo "PASS ${trace_id} — attachment surface binding module satisfies its SMS predicates."
  exit 0
fi

echo "FAIL ${trace_id} — attachment surface binding is unimplemented or diverges from the SMS. Expected failing state until the module exists." >&2
exit 1
