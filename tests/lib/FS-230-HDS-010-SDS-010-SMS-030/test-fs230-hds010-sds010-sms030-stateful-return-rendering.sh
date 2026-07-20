#!/usr/bin/env bash
set -euo pipefail
# GAMP-ID: FS-230-HDS-010-SDS-010-SMS-030
# GAMP-SCOPE: software-module-test
#
# Construction proof for the renderer stateful-return realization
# (SMS-030 Seeded Negative 3 + both recovery branches):
#   1. Negative: a reverse return rule (returnRule / direction=relation-reverse)
#      that carries NO connection-state restriction is reverse-new-flow
#      authority invention. The renderer must fail closed with the SMS-030
#      diagnostic instead of emitting an unconditional reverse interface-pair
#      accept.
#   2. Recovery A (stateful return): the same reverse rule carrying
#      connectionState = "established,related" renders as a `ct state
#      established,related` return rule — never a state-unqualified accept.
#   3. Recovery B (distinct reverse relation): a separately modeled
#      reverse-direction relation with its own bounded tuple (own relationId,
#      relation-forward direction, explicit interfaces) renders as an ordinary
#      independently authorized forward rule.
#   4. An unrecognized connectionState value fails closed instead of being
#      spliced into the ruleset.

repo_root="${SMS_TEST_REPO_ROOT:-$(git -C "$(dirname "${BASH_SOURCE[0]}")" rev-parse --show-toplevel)}"
source "${repo_root}/tests/lib/test-common.sh"

nix_eval_true_or_fail "FS-230-HDS-010-SDS-010-SMS-030 renderer stateful-return realization" \
  env REPO_ROOT="${repo_root}" \
    nix eval \
      --extra-experimental-features 'nix-command flakes' \
      --impure --expr '
        let
          repoRoot = builtins.getEnv "REPO_ROOT";
          flake = builtins.getFlake ("path:" + repoRoot);
          lib = flake.inputs.nixpkgs.lib;

          common = import (repoRoot + "/s88/ControlModule/firewall/lookup/forwarding-intent/common.nix") { inherit lib; };

          pairsFor = rules: import (repoRoot + "/s88/ControlModule/firewall/lookup/forwarding-intent/explicit-pairs.nix") {
            inherit lib common;
            resolveInterfaceTokens = tokens: tokens;
            runtimeTarget = { };
            nodeForwarding = {
              mode = "explicit-policy-forwarding";
              rules = rules;
            };
          };

          renderFor = rules: import (repoRoot + "/s88/ControlModule/firewall/policy/explicit-forwarding.nix") {
            inherit lib;
            escapeComment = value: value;
            forwardingIntent = { normalizedExplicitForwardPairs = pairsFor rules; };
          };

          # CPM relation-reverse record shape (src/cpm/firewall-intent/rules/policy.nix):
          # symmetric return decomposed onto policy interfaces.
          baseReverse = {
            action = "allow";
            relationId = "allow-wan-to-dmz-nebula";
            fromInterface = [ "pol-upstream" ];
            toInterface = [ "pol-downstream" ];
            direction = "relation-reverse";
            returnRule = true;
          };

          # SN3: symmetric converted into an unconditional reverse
          # interface-pair accept (connection state stripped).
          unsafeReverse = builtins.removeAttrs baseReverse [ ];

          # Recovery A: stateful return for the owned forward tuple.
          statefulReverse = baseReverse // { connectionState = "established,related"; };

          # Recovery B: distinct modeled reverse relation with its own bounded
          # tuple — independently authorized, not derived from return behavior.
          distinctReverse = {
            action = "allow";
            relationId = "allow-dmz-nebula-to-wan-reverse-bounded";
            fromInterface = [ "pol-upstream" ];
            toInterface = [ "pol-downstream" ];
            direction = "relation-forward";
            trafficType = "any";
          };

          # Unrecognized connection-state vocabulary must fail closed.
          bogusStateReverse = baseReverse // { connectionState = "new"; };

          negativeEval = builtins.tryEval (builtins.deepSeq (renderFor [ unsafeReverse ]) true);
          bogusEval = builtins.tryEval (builtins.deepSeq (renderFor [ bogusStateReverse ]) true);
          statefulRules = renderFor [ statefulReverse ];
          distinctRules = renderFor [ distinctReverse ];

          checks = {
            # 1. SN3 fails closed: no unconditional reverse accept is rendered.
            unsafeReverseFailsClosed = !negativeEval.success;
            # 2. Recovery A renders a connection-state return rule...
            statefulReverseHasCtState =
              builtins.length statefulRules == 1
              && lib.hasInfix "ct state established,related accept" (builtins.head statefulRules);
            # ... scoped to the reverse interface pair of the owned tuple.
            statefulReverseKeepsPair =
              lib.hasInfix "iifname \"pol-upstream\" oifname \"pol-downstream\"" (builtins.head statefulRules);
            # 3. Recovery B renders the distinct bounded relation as an
            #    ordinary forward rule under its own relation identity.
            distinctReverseRendered =
              builtins.length distinctRules == 1
              && lib.hasInfix "allow-dmz-nebula-to-wan-reverse-bounded" (builtins.head distinctRules)
              && !(lib.hasInfix "ct state" (builtins.head distinctRules));
            # 4. Unrecognized connection-state values fail closed.
            bogusConnectionStateFailsClosed = !bogusEval.success;
          };
          failed = builtins.filter (name: !checks.${name}) (builtins.attrNames checks);
        in
        if failed == [ ] then
          true
        else
          builtins.trace ("failed checks: " + builtins.concatStringsSep ", " failed) false
      '

echo "PASS FS-230-HDS-010-SDS-010-SMS-030: renderer stateful-return realization"

# SN3 diagnostic content: the fail-closed rejection must name the SMS, the
# offending rule, and the recovery options (stateful return or a distinct
# reverse relation) — proving the rejection is the SMS-030 authority guard,
# not an unrelated evaluation error.
sn3_stderr="$(mktemp)"
trap 'rm -f "${sn3_stderr}"' EXIT
set +e
env REPO_ROOT="${repo_root}" \
  nix eval \
    --extra-experimental-features 'nix-command flakes' \
    --impure --json --expr '
      let
        repoRoot = builtins.getEnv "REPO_ROOT";
        flake = builtins.getFlake ("path:" + repoRoot);
        lib = flake.inputs.nixpkgs.lib;
        common = import (repoRoot + "/s88/ControlModule/firewall/lookup/forwarding-intent/common.nix") { inherit lib; };
        pairs = import (repoRoot + "/s88/ControlModule/firewall/lookup/forwarding-intent/explicit-pairs.nix") {
          inherit lib common;
          resolveInterfaceTokens = tokens: tokens;
          runtimeTarget = { };
          nodeForwarding = {
            mode = "explicit-policy-forwarding";
            rules = [
              {
                action = "allow";
                relationId = "allow-wan-to-dmz-nebula";
                fromInterface = [ "pol-upstream" ];
                toInterface = [ "pol-downstream" ];
                direction = "relation-reverse";
                returnRule = true;
              }
            ];
          };
        };
      in pairs
    ' >/dev/null 2>"${sn3_stderr}"
sn3_status=$?
set -e
if [[ "${sn3_status}" -eq 0 ]]; then
  echo "FAIL FS-230-HDS-010-SDS-010-SMS-030: state-unqualified reverse return rule was accepted (unconditional reverse interface-pair accept still open)" >&2
  exit 1
fi
grep -Fq "FS-230-HDS-010-SDS-010-SMS-030: reverse return rule 'allow-wan-to-dmz-nebula' carries no connection-state restriction (reverse-new-flow authority invention)" "${sn3_stderr}" || {
  echo "FAIL FS-230-HDS-010-SDS-010-SMS-030: reverse-new-flow rejection lacked the SMS-030 diagnostic" >&2
  cat "${sn3_stderr}" >&2
  exit 1
}
echo "PASS FS-230-HDS-010-SDS-010-SMS-030: reverse-new-flow invention fails closed with SMS-030 diagnostic"
