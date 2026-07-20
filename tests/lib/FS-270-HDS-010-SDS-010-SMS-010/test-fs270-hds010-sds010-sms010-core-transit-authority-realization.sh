#!/usr/bin/env bash
set -euo pipefail
# GAMP-ID: FS-270-HDS-010-SDS-010-SMS-010
# GAMP-SCOPE: software-module-test
#
# Renderer-side faithful, fail-closed realization of the corrected CPM
# core-transit authority (the 2026-07-15 production ppp0 classification
# defect was CPM-owned; the renderer must realize the corrected authority
# exactly and never resurrect the denied bypass from topology roles):
#
#   P1 (faithful): a corrected CPM explicit-core-forwarding handoff — mesh
#      accepts for the admitted dedicated pair only, NO rule touching the
#      denied external ppp0 surface, transitAdmission.denied naming it —
#      realizes exactly the CPM-authorized pairs. No rendered forward pair
#      touches ppp0 or pairs ens3 with ppp0, even though the interface
#      topology (roles: lan ens21/ens22, wan ens3/ppp0) still knows both
#      surfaces.
#   P2 (fail-closed, all-denied core): the same explicit-core-forwarding
#      handoff with rules == [ ] (every transit surface denied) realizes
#      ZERO lan-to-wan forward pairs — the legacy role-derived
#      core-lan-to-wan fallback must NOT be invented, and the forwarding
#      intent stays authoritative (no downstream fallback derivation).
#   SN1 (guard proof): the same node WITHOUT the explicit CPM handoff
#      (legacy shape: no mode/rules) still derives the role-based
#      core-lan-to-wan pair touching ppp0 — proving P1/P2 pass because of
#      the CPM-authority realization, not because the fixture is empty of
#      the bypass class (active seeded negative for the guard).
#
# This is renderer SMT construction evidence for the realization boundary
# only; it does not re-own the CPM classification defect and does not claim
# SIT/HAT/SAT runtime acceptance.

repo_root="${SMS_TEST_REPO_ROOT:-$(git -C "$(dirname "${BASH_SOURCE[0]}")" rev-parse --show-toplevel)}"
source "${repo_root}/tests/lib/test-common.sh"

nix_eval_true_or_fail "FS-270-HDS-010-SDS-010-SMS-010 renderer core-transit authority realization" \
  env REPO_ROOT="${repo_root}" \
    nix eval \
      --extra-experimental-features 'nix-command flakes' \
      --impure --expr '
        let
          repoRoot = builtins.getEnv "REPO_ROOT";
          flake = builtins.getFlake ("path:" + repoRoot);
          lib = flake.inputs.nixpkgs.lib;

          forwardingIntentFor = runtimeTarget:
            import (repoRoot + "/s88/ControlModule/firewall/lookup/forwarding-intent.nix") {
              inherit lib runtimeTarget;
              interfaces = { };
              wanIfs = [ "ens3" "ppp0" ];
              lanIfs = [ "ens21" "ens22" ];
            };

          coreViewFor = runtimeTarget:
            let
              fi = forwardingIntentFor runtimeTarget;
            in
            import (repoRoot + "/s88/ControlModule/firewall/policy/core/forwarding.nix") {
              inherit lib;
              forwardingIntent = fi;
              uplinks = { };
              wanNames = [ "ens3" "ppp0" ];
              lanNames = [ "ens21" "ens22" ];
              forwardEgressNames = [ "ens3" "ppp0" ];
              overlayIngressNames = [ ];
              adapterNames = [ ];
            };

          # Corrected CPM core handoff: the dedicated modeled pair is
          # admitted; the external ppp0 surface is denied fail-closed and no
          # emitted rule touches it (CPM commit-6463219 output shape).
          correctedRules = [
            {
              action = "accept";
              fromInterface = "ens21";
              toInterface = "ens22";
              relationId = "core-transit-mesh--link::a--link::b";
              comment = "core-transit-mesh--link::a--link::b";
              direction = "core-transit-mesh";
              trafficType = "any";
              transportAuthority = {
                basis = "dedicated-link-isolation";
                provenanceIsAuthority = false;
              };
            }
            {
              action = "accept";
              fromInterface = "ens22";
              toInterface = "ens21";
              relationId = "core-transit-mesh--link::b--link::a";
              comment = "core-transit-mesh--link::b--link::a";
              direction = "core-transit-mesh";
              trafficType = "any";
              transportAuthority = {
                basis = "dedicated-link-isolation";
                provenanceIsAuthority = false;
              };
            }
          ];

          correctedCore = {
            forwarding = {
              mode = "explicit-core-forwarding";
              rules = correctedRules;
              transitAdmission = {
                module = "FS-270-HDS-010-SDS-010-SMS-010";
                denied = [
                  {
                    surface = "ppp0";
                    reason = "external-surface-not-core-transit";
                    failClosed = true;
                    diagnostic = "core-transit-admission-denied";
                  }
                ];
              };
            };
          };

          allDeniedCore = {
            forwarding = {
              mode = "explicit-core-forwarding";
              rules = [ ];
              transitAdmission = {
                module = "FS-270-HDS-010-SDS-010-SMS-010";
                denied = [
                  {
                    surface = "ppp0";
                    reason = "external-surface-not-core-transit";
                    failClosed = true;
                  }
                ];
              };
            };
          };

          # Legacy shape: no explicit CPM forwarding handoff at all.
          legacyCore = { };

          corrected = coreViewFor correctedCore;
          allDenied = coreViewFor allDeniedCore;
          legacy = coreViewFor legacyCore;

          pairTouches = ifName: pair:
            builtins.elem ifName (pair."in" or [ ])
            || builtins.elem ifName (pair."out" or [ ]);

          checks = {
            # P1: exactly the CPM-authorized pairs are realized.
            correctedRealizesExactlyCpmPairs =
              builtins.length corrected.forwardPairs == 2
              && builtins.all
                (pair:
                  (pair."in" == [ "ens21" ] && pair."out" == [ "ens22" ])
                  || (pair."in" == [ "ens22" ] && pair."out" == [ "ens21" ]))
                corrected.forwardPairs;
            # P1: the denied external surface is never realized.
            correctedNeverTouchesDeniedSurface =
              !(builtins.any (pairTouches "ppp0") corrected.forwardPairs);
            correctedKeepsCpmRelationIdentity =
              builtins.all
                (pair: lib.hasPrefix "core-transit-mesh--" (pair.comment or ""))
                corrected.forwardPairs;
            # P2: all transit denied -> zero pairs, no role fallback.
            allDeniedRealizesZeroPairs = allDenied.forwardPairs == [ ];
            # SN1: without the explicit CPM handoff the legacy role fallback
            # DOES invent a lan-to-wan pair touching ppp0 — the guard under
            # test is the CPM-authority realization, not an empty fixture.
            legacyFallbackWouldTouchDeniedSurface =
              builtins.any (pairTouches "ppp0") legacy.forwardPairs;
          };
          failed = builtins.filter (name: !checks.${name}) (builtins.attrNames checks);
        in
        if failed == [ ] then
          true
        else
          builtins.trace ("failed checks: " + builtins.concatStringsSep ", " failed) false
      '

echo "PASS FS-270-HDS-010-SDS-010-SMS-010: renderer faithful fail-closed core-transit authority realization"
