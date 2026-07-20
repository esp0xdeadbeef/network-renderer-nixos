#!/usr/bin/env bash
# GAMP-ID: FS-500-HDS-010-SDS-010-SMS-010
# GAMP-ID: FS-500-HDS-010-SDS-010-SMS-030
set -euo pipefail

repo_root="${SMS_TEST_REPO_ROOT:-$(git -C "$(dirname "${BASH_SOURCE[0]}")" rev-parse --show-toplevel)}"
source "${repo_root}/tests/lib/test-common.sh"

example_root="${repo_root}/tests/fixtures/s-router-overlay-dns-lane-policy"
result_json="$(mktemp)"
eval_stderr="$(mktemp)"
checks_json="$(mktemp)"
trap 'rm -f "${result_json}" "${eval_stderr}" "${checks_json}"' EXIT

nix_eval_json_or_fail \
  fs500-dns-hat-evidence-debug-payload \
  "${result_json}" \
  "${eval_stderr}" \
  env REPO_ROOT="${repo_root}" \
    nix eval \
    --extra-experimental-features 'nix-command flakes' \
    --impure --json --expr '
      let
        repoRoot = builtins.getEnv "REPO_ROOT";
        flake = builtins.getFlake ("path:" + repoRoot);
        lib = flake.inputs.nixpkgs.lib;
        host = import (repoRoot + "/tests/nix/build-host-from-paths.nix") {
          selector = "s-router-test";
          system = "x86_64-linux";
          intentPath = repoRoot + "/tests/fixtures/s-router-overlay-dns-lane-policy/intent.nix";
          inventoryPath = repoRoot + "/tests/fixtures/s-router-overlay-dns-lane-policy/inventory-nixos.nix";
        };

        sortedAttrNames = attrs: lib.sort builtins.lessThan (builtins.attrNames attrs);
        concatMap = f: xs: builtins.concatLists (map f xs);
        firstNonEmptyString =
          values:
          let
            strings = lib.filter (value: builtins.isString value && value != "") values;
          in
          if strings == [ ] then "" else builtins.head strings;

        collectTrafficPathValidations =
          value:
          let
            current =
              if builtins.isAttrs value
                && value ? trafficPathValidation
                && builtins.isAttrs value.trafficPathValidation then
                [ value.trafficPathValidation ]
              else
                [ ];
            children =
              if builtins.isAttrs value then
                concatMap (name: collectTrafficPathValidations value.${name}) (sortedAttrNames value)
              else
                [ ];
          in
          current ++ children;

        trafficPathValidations =
          collectTrafficPathValidations (host.controlPlaneOut.control_plane_model.data or { });

        validPathRows =
          concatMap
            (validation:
              let
                paths = validation.validPaths or [ ];
              in
              if builtins.isList paths then paths else [ ])
            trafficPathValidations;
      in
      {
        trafficPathValidationCount = builtins.length trafficPathValidations;
        validPathIds =
          lib.filter (value: value != "")
            (map
              (path: firstNonEmptyString [ (path.relationId or "") (path.p2pIsolationKey or "") ])
              validPathRows);
        evidence = host.debugPayload.dnsHatEvidence or [ ];
      }
    '

_jq '
  def row($spec):
    [.evidence[] | select(.spec == $spec)];
  def one_row($spec):
    (row($spec) | length) == 1;
  def non_empty($path):
    getpath($path) != null and getpath($path) != "";

  row("FS-500-HDS-010-SDS-010-SMS-010")[0] as $decision
  | row("FS-500-HDS-010-SDS-010-SMS-030")[0] as $reason
  | {
      checks: {
        traffic_path_validation_source_exists: (.trafficPathValidationCount > 0),
        reachability_row_present_once: one_row("FS-500-HDS-010-SDS-010-SMS-010"),
        decision_reason_row_present_once: one_row("FS-500-HDS-010-SDS-010-SMS-030"),
        reachability_row_uses_cpm_source: (($decision.source // "") | contains("trafficPathValidation.validPaths")),
        decision_reason_uses_cpm_source: (($reason.source // "") | contains("trafficPathValidation")),
        selected_path_matches_cpm_valid_path: (.validPathIds | index($decision.decision.selectedPath) != null),
        reachability_decision_result: ($decision | non_empty(["decision", "result"])),
        reachability_traffic_class: ($decision | non_empty(["decision", "trafficClass"])),
        reachability_selected_path: ($decision | non_empty(["decision", "selectedPath"])),
        reachability_egress_surface: ($decision.decision | has("egressSurface")),
        reachability_return_behavior: ($decision | non_empty(["decision", "returnBehavior"])),
        reachability_service_exposure: ($decision | non_empty(["decision", "serviceExposure"])),
        diagnostic_reason: ($reason | non_empty(["diagnostic", "reason"])),
        diagnostic_reason_class: ($reason | non_empty(["diagnostic", "reasonClass"])),
        diagnostic_first_blocker: ($reason | non_empty(["diagnostic", "firstBlocker"]))
      }
    }
  | .ok = ([.checks[]] | all)
  | .failed = (.checks | to_entries | map(select(.value | not) | .key))
' "${result_json}" > "${checks_json}"

assert_json_checks_ok fs500-dns-hat-evidence-debug-payload "${checks_json}"

echo "PASS fs500-dns-hat-evidence-debug-payload"
