#!/usr/bin/env bash
set -euo pipefail
# GAMP-ID: FS-230-HDS-010-SDS-010-SMS-020
# GAMP-SCOPE: software-module-test
#
# Construction proof for the renderer materialization of the public-ingress
# translation decision (SMS-020 Seeded Negative 3 + recovery):
#   1. A service forward carrying translationMode = "none" is an explicit
#      no-translation decision: renderServiceForward emits NO `dnat to` and
#      renderServiceSnat emits NO masquerade for that tuple. The service is
#      still reachable (accept rules present).
#   2. The SAME forward flipped to a translation-capable mode (napt) materializes
#      the DNAT contract (`dnat to <target>`) and the SNAT masquerade — proving
#      the no-translation suppression is a genuine decision, not a renderer that
#      never emits DNAT at all.
set -euo pipefail

repo_root="${SMS_TEST_REPO_ROOT:-$(git -C "$(dirname "${BASH_SOURCE[0]}")" rev-parse --show-toplevel)}"
source "${repo_root}/tests/lib/test-common.sh"

nix_eval_true_or_fail "FS-230-HDS-010-SDS-010-SMS-020 renderer no-translation decision materialization" \
  env REPO_ROOT="${repo_root}" \
    nix eval \
      --extra-experimental-features 'nix-command flakes' \
      --impure --expr '
        let
          repoRoot = builtins.getEnv "REPO_ROOT";
          flake = builtins.getFlake ("path:" + repoRoot);
          lib = flake.inputs.nixpkgs.lib;

          rules = import (repoRoot + "/s88/ControlModule/module/public-ingress/rules.nix") { inherit lib; };

          forwardFor = mode: {
            serviceName = "dmz-nebula";
            comment = "s88-public-service-dmz-nebula";
            targetIPv4 = "10.90.10.100";
            translationMode = mode;
            publicIPv4 = "203.0.113.10";
            matches = [
              { proto = "udp"; dports = [ 4242 ]; }
              { proto = "tcp"; dports = [ 4242 ]; }
            ];
          };

          noneForward = forwardFor "none";
          naptForward = forwardFor "napt";
          # SMS Negative case 1 (missing mode field): a service forward whose
          # owning authority never declared translationMode must fail closed
          # instead of materializing legacy DNAT/SNAT.
          missingModeForward =
            builtins.removeAttrs (forwardFor "none") [ "translationMode" ];

          noneDnat = rules.renderServiceForward "br-wan" noneForward;
          noneSnat = rules.renderServiceSnat noneForward;
          noneAccept = rules.renderServiceAccept "br-wan" noneForward;

          naptDnat = rules.renderServiceForward "br-wan" naptForward;
          naptSnat = rules.renderServiceSnat naptForward;

          checks = {
            # 1. translationMode=none => no dnat, no masquerade for this tuple.
            noneEmitsNoDnat = !lib.hasInfix "dnat to" noneDnat;
            noneEmitsNoMasquerade = !lib.hasInfix "masquerade" noneSnat;
            # ... but the service is still reachable (accept rules present).
            noneStillReachable =
              lib.hasInfix "accept comment" noneAccept
              && lib.hasInfix "dport 4242" noneAccept;
            # 2. Recovery: translation-capable mode materializes the DNAT contract.
            naptEmitsDnat =
              lib.hasInfix "dnat to 10.90.10.100" naptDnat
              && lib.hasInfix "udp dport 4242" naptDnat
              && lib.hasInfix "tcp dport 4242" naptDnat;
            naptEmitsMasquerade =
              lib.hasInfix "ct status dnat masquerade" naptSnat;
            # 3. Missing translationMode: renderServiceForward and
            #    renderServiceSnat refuse legacy DNAT/SNAT materialization
            #    (fail closed) instead of defaulting to a permissive mode.
            missingModeDnatFailsClosed =
              !(builtins.tryEval (rules.renderServiceForward "br-wan" missingModeForward)).success;
            missingModeSnatFailsClosed =
              !(builtins.tryEval (rules.renderServiceSnat missingModeForward)).success;
          };
          failed = builtins.filter (name: !checks.${name}) (builtins.attrNames checks);
        in
        if failed == [ ] then
          true
        else
          builtins.trace ("failed checks: " + builtins.concatStringsSep ", " failed) false
      '

echo "PASS FS-230-HDS-010-SDS-010-SMS-020: renderer no-translation decision materialization"

# SMS Negative case 1 (missing mode field), ingress-path diagnostic: a modeled
# service tuple whose owning external allow relation carries returnBehavior and
# sourcePreservation but no translationMode must fail closed at service-ingress
# derivation with a diagnostic naming the service tuple and the missing mode
# field — never fall through to legacy DNAT materialization.
missing_mode_stderr="$(mktemp)"
trap 'rm -f "${missing_mode_stderr}"' EXIT
set +e
env REPO_ROOT="${repo_root}" \
  nix eval \
    --extra-experimental-features 'nix-command flakes' \
    --impure --json --expr '
      let
        repoRoot = builtins.getEnv "REPO_ROOT";
        flake = builtins.getFlake ("path:" + repoRoot);
        lib = flake.inputs.nixpkgs.lib;
        facts = import (repoRoot + "/s88/ControlModule/module/public-ingress/facts.nix") { inherit lib; };
        cpmRoot = {
          ent.site1 = {
            policy.endpointBindings.services.dmz-nebula.providers = [ "isp-a" ];
            communicationContract.relations = [
              {
                action = "allow";
                id = "allow-wan-to-dmz-nebula";
                from = { kind = "external"; name = "wan"; };
                to = { kind = "service"; name = "dmz-nebula"; };
                match = [ { proto = "udp"; dports = [ 4242 ]; } ];
                publicIngressTupleAuthority = {
                  returnBehavior = "stateful-return";
                  sourcePreservation = "preserve-source";
                };
              }
            ];
            services = [
              { name = "dmz-nebula"; providerEndpoints = [ { ipv4 = [ "10.90.10.100" ]; } ]; }
            ];
          };
        };
        publicIngressFacts.services.ent.site1.dmz-nebula = { publicIPv4 = "203.0.113.10"; };
        ingresses = facts.serviceIngressesFor { inherit cpmRoot publicIngressFacts; };
      in
        map (forward: forward.translationMode) ingresses
    ' >/dev/null 2>"${missing_mode_stderr}"
missing_mode_status=$?
set -e
if [[ "${missing_mode_status}" -eq 0 ]]; then
  echo "FAIL FS-230-HDS-010-SDS-010-SMS-020: missing translationMode was accepted at service-ingress derivation (legacy DNAT path still open)" >&2
  exit 1
fi
grep -Fq "FS-230-HDS-010-SDS-010-SMS-020: public-ingress service tuple 'dmz-nebula' has no owning relation declaring publicIngressTupleAuthority.translationMode" "${missing_mode_stderr}" || {
  echo "FAIL FS-230-HDS-010-SDS-010-SMS-020: missing-mode rejection lacked the ingress-path diagnostic" >&2
  cat "${missing_mode_stderr}" >&2
  exit 1
}
echo "PASS FS-230-HDS-010-SDS-010-SMS-020: missing translationMode fails closed at service-ingress derivation with ingress-path diagnostic"
