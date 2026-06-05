#!/usr/bin/env bash
# GAMP-ID: FS-100-HDS-010-SDS-010-SMS-010
# GAMP-ID: FS-100-HDS-010-SDS-010-SMS-040
# GAMP-ID: FS-100-HDS-010-SDS-010-SMS-050
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${repo_root}/tests/lib/test-common.sh"

render_json="$(mktemp)"
eval_stderr="$(mktemp)"
tmp_dir="$(mktemp -d "${TMPDIR:-/tmp}/network-renderer-nixos-fs100-provenance.XXXXXX")"
trap 'rm -f "${render_json}" "${eval_stderr}"; rm -rf "${tmp_dir}"' EXIT

labs_root="$(flake_input_path network-labs)"
example_dir="${labs_root}/examples/single-wan"
cpm_json="${tmp_dir}/cpm.json"

build_cpm_json "${example_dir}/intent.nix" "${example_dir}/inventory-nixos.nix" "${cpm_json}"

nix_eval_json_or_fail \
  fs100-renderer-output-provenance \
  "${render_json}" \
  "${eval_stderr}" \
  env REPO_ROOT="${repo_root}" CPM_PATH="${cpm_json}" INVENTORY_PATH="${example_dir}/inventory-nixos.nix" \
    nix eval \
    --extra-experimental-features 'nix-command flakes' \
    --impure --json --expr '
      let
        flake = builtins.getFlake ("path:" + builtins.getEnv "REPO_ROOT");
        cpmBase = builtins.fromJSON (builtins.readFile (builtins.getEnv "CPM_PATH"));
        cpm = cpmBase // {
          meta = (cpmBase.meta or { }) // {
            sourceClasses = {
              userIntent = {
                path = "examples/fs100/intent.nix";
                narHash = "sha256-intent";
              };
              publicInventory = {
                path = "examples/fs100/inventory-nixos.nix";
                narHash = "sha256-public-inventory";
              };
              protectedInventory = {
                ref = "sops://examples/fs100/protected.yaml";
                secretValue = "PLAINTEXT-PROTECTED-VALUE";
              };
              runtimeFacts = {
                ref = "runtime://provider/public-addresses";
              };
              validationContext = {
                profile = "renderer-construction";
              };
            };
            requested = {
              scope = {
                site = "nixos";
                host = "s-router-nixos";
              };
              target = {
                renderer = "nixos";
                role = "renderer-output";
              };
            };
            locks = {
              network-control-plane-model = {
                rev = "1111222233334444555566667777888899990000";
                narHash = "sha256-cpm";
              };
            };
            controlledBaseline = "fs100-renderer-output-provenance";
          };
        };
        rendered = flake.lib.renderer.renderDryConfig {
          inherit cpm;
          inventoryPath = builtins.getEnv "INVENTORY_PATH";
          exampleDir = builtins.dirOf (builtins.getEnv "CPM_PATH");
          debug = true;
        };
      in rendered
    '

if rg -qF "PLAINTEXT-PROTECTED-VALUE" "${render_json}"; then
  fail "FAIL fs100-renderer-output-provenance: protected value leaked into rendered artifact"
fi

checks_json="${tmp_dir}/checks.json"
_jq '
  .metadata.provenance as $p
  | {
      checks: {
        protected_value_redacted: ($p.sources.sourceClasses.protectedInventory.secretValue == "<redacted>"),
        debug_control_plane_redacted: (.debug.controlPlane.meta.sourceClasses.protectedInventory.secretValue == "<redacted>"),
        source_user_intent_preserved: ($p.sources.sourceClasses.userIntent.path == "examples/fs100/intent.nix"),
        source_public_inventory_preserved: ($p.sources.sourceClasses.publicInventory.path == "examples/fs100/inventory-nixos.nix"),
        runtime_facts_preserved: ($p.sources.sourceClasses.runtimeFacts.ref == "runtime://provider/public-addresses"),
        validation_context_preserved: ($p.sources.sourceClasses.validationContext.profile == "renderer-construction"),
        requested_scope_preserved: ($p.requested.scope.site == "nixos"),
        requested_target_preserved: ($p.requested.target.renderer == "nixos"),
        derived_runtime_target_bound: (($p.requested.derivedScope.runtimeTargets | length) > 0),
        upstream_lock_preserved: ($p.locks.upstream."network-control-plane-model".rev == "1111222233334444555566667777888899990000"),
        renderer_lock_available: ($p.locks.renderer.available == true),
        output_artifact_bound: ($p.output.kind == "nixos-dry-config" and $p.output.artifact == "90-dry-config.json"),
        controlled_baseline_bound: ($p.controlledBaseline == "fs100-renderer-output-provenance")
      }
    }
  | .ok = ([.checks[]] | all)
  | .failed = (.checks | to_entries | map(select(.value | not) | .key))
' "${render_json}" > "${checks_json}"

assert_json_checks_ok fs100-renderer-output-provenance "${checks_json}"

echo "PASS fs100-renderer-output-provenance"
