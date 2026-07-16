#!/usr/bin/env bash
# GAMP-ID: FS-310-HDS-020-SDS-010-SMS-075
# GAMP-SCOPE: software-module-test
#
# Construction handoff for SMS-075 (renderer core-ingress DNAT materialization):
#   1. A missing source core-ingress tuple is diagnosed as source/input NOT OK
#      (empty prerouting chain, no dnat rule).
#   2. A modeled UDP 4242 core-ingress tuple emits a source-bound
#      prerouting/dstnat DNAT rule to the modeled target endpoint and port.
#   3. TCP and UDP legs are checked independently.
#   4. Postrouting masquerade or generic forward rules cannot satisfy DNAT
#      materialization.
#   5. Seeded negative case 3 (synthetic-only DNAT proof): runtime forwards
#      with NO corresponding public-ingress authority in the CPM artifact are
#      rejected with diagnostic.synthetic-core-ingress-authority instead of
#      materializing DNAT; recovery is the CPM-authority-backed fixture above.
#   6. Seeded negative case 5 (no-translation mode): the same complete
#      authority tuple with translationMode = "none" emits no DNAT rule;
#      restoring the napt mode recovers the DNAT materialization.
#
# Fixture models the 2026-07-13 live observation: core-owned ingress address
# 217.148.134.173, ingress surface ppp0, protocol udp/tcp, ingress port 4242,
# target 192.168.3.10:4242, translation mode DNAT/NAPT.
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${repo_root}/tests/lib/test-common.sh"

nix_eval_true_or_fail "FS-310-HDS-020-SDS-010-SMS-075 core-ingress DNAT materialization" \
  env REPO_ROOT="${repo_root}" \
    nix eval \
      --extra-experimental-features 'nix-command flakes' \
      --impure --expr '
        let
          repoRoot = builtins.getEnv "REPO_ROOT";
          flake = builtins.getFlake ("path:" + repoRoot);
          lib = flake.inputs.nixpkgs.lib;

          renderIngress = forwards:
            (import (repoRoot + "/s88/ControlModule/module/public-ingress.nix") {
              inherit lib;
              hostName = "s-router";
              # FS-310-HDS-010-SDS-010-SMS-130: runtime forwards are runtime
              # facts, not authority. The CPM artifact must carry the owning
              # public-ingress authority (external allow service relation with
              # publicIngressTupleAuthority whose provider endpoint owns the
              # target address); a synthetic-only forward fails closed.
              controlPlane = {
                data = {
                  esp.site-a = {
                    policy.endpointBindings.services.core-nebula.providers = [ "isp-a" ];
                    communicationContract.relations = [
                      {
                        action = "allow";
                        id = "allow-wan-to-core-nebula";
                        from = { kind = "external"; name = "wan"; };
                        to = { kind = "service"; name = "core-nebula"; };
                        match = [
                          { proto = "udp"; dports = [ 4242 ]; }
                          { proto = "tcp"; dports = [ 4242 ]; }
                        ];
                        publicIngressTupleAuthority = {
                          translationMode = "napt";
                          returnBehavior = "stateful-return";
                        };
                      }
                    ];
                    services = [
                      {
                        name = "core-nebula";
                        providerEndpoints = [ { ipv4 = [ "192.168.3.10" ]; } ];
                      }
                    ];
                  };
                };
              };
              runtimeFacts.publicIngress = {
                bridgeInterface = "ppp0";
                snatSourceCidr4 = "192.168.3.0/24";
                runtimeForwards = forwards;
              };
            }).networking.nftables.ruleset;

          nebulaForward = protocols: {
            publicIPv4 = "217.148.134.173";
            targetIPv4 = "192.168.3.10";
            inherit protocols;
            inputDports = [ 4242 ];
            protectServiceDports = false;
            comment = "fs310-sms075-nebula-4242";
          };

          # Negative case 1: source lacks the core-ingress tuple.
          emptyRuleset = renderIngress [ ];
          # Both legs: modeled udp + tcp 4242 core-ingress tuple.
          bothRuleset = renderIngress [ (nebulaForward [ "tcp" "udp" ]) ];
          # Independent-leg check: only the tcp leg is modeled.
          tcpOnlyRuleset = renderIngress [ (nebulaForward [ "tcp" ]) ];
          # Independent-leg check: only the udp leg is modeled.
          udpOnlyRuleset = renderIngress [ (nebulaForward [ "udp" ]) ];

          # Extract just the nat prerouting chain body from a ruleset so
          # postrouting masquerade cannot be mistaken for DNAT materialization.
          preroutingBody = ruleset:
            let
              afterHead = lib.last (lib.splitString "chain prerouting {" ruleset);
              body = builtins.head (lib.splitString "}" afterHead);
            in
            body;

          udpDnatRule = "meta l4proto udp udp dport 4242 dnat to 192.168.3.10";
          tcpDnatRule = "meta l4proto tcp tcp dport 4242 dnat to 192.168.3.10";

          checks = {
            # 1. Missing source tuple -> source/input NOT OK: prerouting has no
            #    dnat rule (empty chain body), only postrouting masquerade exists.
            missingTupleEmptyPrerouting =
              !lib.hasInfix "dnat to" (preroutingBody emptyRuleset);
            missingTupleStillHasMasquerade =
              lib.hasInfix "masquerade comment \"s88-host-public-ingress-snat\"" emptyRuleset;

            # 2. Modeled UDP 4242 tuple emits a source-bound prerouting/dstnat
            #    DNAT rule to the modeled target endpoint and port.
            udpLegDnatMaterialized =
              lib.hasInfix "ip daddr 217.148.134.173 ${udpDnatRule}" (preroutingBody bothRuleset);
            preroutingHookIsDstnat =
              lib.hasInfix "type nat hook prerouting priority dstnat" bothRuleset;

            # 3. TCP and UDP legs are independent.
            tcpLegDnatMaterialized =
              lib.hasInfix "ip daddr 217.148.134.173 ${tcpDnatRule}" (preroutingBody bothRuleset);
            tcpOnlyHasNoUdpLeg =
              lib.hasInfix tcpDnatRule (preroutingBody tcpOnlyRuleset)
              && !lib.hasInfix udpDnatRule (preroutingBody tcpOnlyRuleset);
            udpOnlyHasNoTcpLeg =
              lib.hasInfix udpDnatRule (preroutingBody udpOnlyRuleset)
              && !lib.hasInfix tcpDnatRule (preroutingBody udpOnlyRuleset);

            # 4. Postrouting masquerade / generic forward cannot satisfy DNAT.
            #    The full fixture must carry a real dnat rule AND the companion
            #    forward allow; masquerade alone (as in the empty fixture) is not
            #    core-ingress materialization.
            masqueradeAloneNotDnat =
              lib.hasInfix "masquerade" bothRuleset
              && lib.hasInfix "dnat to 192.168.3.10" (preroutingBody bothRuleset);
            companionForwardAllowPresent =
              lib.hasInfix "oifname \"ppp0\" ip daddr 192.168.3.10 meta l4proto udp udp dport 4242 accept" bothRuleset
              && lib.hasInfix "oifname \"ppp0\" ip daddr 192.168.3.10 meta l4proto tcp tcp dport 4242 accept" bothRuleset;
          };

          failed = lib.attrNames (lib.filterAttrs (_: v: v != true) checks);
        in
        if failed == [ ] then
          true
        else
          builtins.trace "failed checks: ${builtins.toJSON failed}" false
      '

pass "FS-310-HDS-020-SDS-010-SMS-075 core-ingress DNAT materialization"

# --- Seeded negative case 3: synthetic-only DNAT proof -----------------------
# A caller-created public address / ingress interface / target / protocol /
# port runtime forward with NO corresponding core-ingress authority tuple in
# the CPM artifact must be rejected as diagnostic.synthetic-core-ingress-authority.
# Helper output alone is not an integrated renderer result. The recovery
# assertion is the CPM-authority-backed fixture proven in the stanza above:
# the same tuple carried by the CPM artifact renders the source-bound DNAT.
n3_stderr="$(mktemp)"
trap 'rm -f "${n3_stderr}"' EXIT
set +e
env REPO_ROOT="${repo_root}" \
  nix eval \
    --extra-experimental-features 'nix-command flakes' \
    --impure --json --expr '
      let
        repoRoot = builtins.getEnv "REPO_ROOT";
        flake = builtins.getFlake ("path:" + repoRoot);
        lib = flake.inputs.nixpkgs.lib;
      in
      (import (repoRoot + "/s88/ControlModule/module/public-ingress.nix") {
        inherit lib;
        hostName = "s-router";
        controlPlane = { data = { }; };
        runtimeFacts.publicIngress = {
          bridgeInterface = "ppp0";
          snatSourceCidr4 = "192.168.3.0/24";
          runtimeForwards = [
            {
              publicIPv4 = "217.148.134.173";
              targetIPv4 = "192.168.3.10";
              protocols = [ "udp" "tcp" ];
              inputDports = [ 4242 ];
              protectServiceDports = false;
              comment = "fs310-sms075-synthetic-only";
            }
          ];
        };
      }).networking.nftables.ruleset
    ' >/dev/null 2>"${n3_stderr}"
n3_status=$?
set -e
if [[ "${n3_status}" -eq 0 ]]; then
  echo "FAIL FS-310-HDS-020-SDS-010-SMS-075: negative case 3 — synthetic-only runtime forward materialized DNAT without CPM authority" >&2
  exit 1
fi
grep -Fq "diagnostic.synthetic-core-ingress-authority" "${n3_stderr}" || {
  echo "FAIL FS-310-HDS-020-SDS-010-SMS-075: negative case 3 — rejection lacked diagnostic.synthetic-core-ingress-authority" >&2
  cat "${n3_stderr}" >&2
  exit 1
}
pass "FS-310-HDS-020-SDS-010-SMS-075 negative case 3: synthetic-only DNAT proof rejected (diagnostic.synthetic-core-ingress-authority)"

# --- Seeded negative case 5: no-translation mode ------------------------------
# The complete authority tuple with translationMode = "none" shall emit no DNAT
# for that tuple. The napt-mode stanza above is the explicit recovery: the same
# tuple with a DNAT-capable mode materializes the source-bound DNAT rule.
nix_eval_true_or_fail "FS-310-HDS-020-SDS-010-SMS-075 negative case 5: translationMode=none emits no DNAT" \
  env REPO_ROOT="${repo_root}" \
    nix eval \
      --extra-experimental-features 'nix-command flakes' \
      --impure --expr '
        let
          repoRoot = builtins.getEnv "REPO_ROOT";
          flake = builtins.getFlake ("path:" + repoRoot);
          lib = flake.inputs.nixpkgs.lib;
          ruleset =
            (import (repoRoot + "/s88/ControlModule/module/public-ingress.nix") {
              inherit lib;
              hostName = "s-router";
              controlPlane = {
                data = {
                  esp.site-a = {
                    policy.endpointBindings.services.core-nebula.providers = [ "isp-a" ];
                    communicationContract.relations = [
                      {
                        action = "allow";
                        id = "allow-wan-to-core-nebula";
                        from = { kind = "external"; name = "wan"; };
                        to = { kind = "service"; name = "core-nebula"; };
                        match = [
                          { proto = "udp"; dports = [ 4242 ]; }
                          { proto = "tcp"; dports = [ 4242 ]; }
                        ];
                        publicIngressTupleAuthority = {
                          translationMode = "none";
                          returnBehavior = "stateful-return";
                        };
                      }
                    ];
                    services = [
                      {
                        name = "core-nebula";
                        providerEndpoints = [ { ipv4 = [ "192.168.3.10" ] ; } ];
                      }
                    ];
                  };
                };
              };
              runtimeFacts.publicIngress = {
                bridgeInterface = "ppp0";
                snatSourceCidr4 = "192.168.3.0/24";
                runtimeForwards = [
                  {
                    publicIPv4 = "217.148.134.173";
                    targetIPv4 = "192.168.3.10";
                    protocols = [ "udp" "tcp" ];
                    inputDports = [ 4242 ];
                    protectServiceDports = false;
                    comment = "fs310-sms075-no-translation";
                  }
                ];
              };
            }).networking.nftables.ruleset;
          checks = {
            noDnatForTuple = !lib.hasInfix "dnat to 192.168.3.10" ruleset;
            rulesetStillRenders = lib.hasInfix "type nat hook prerouting priority dstnat" ruleset;
          };
          failed = builtins.filter (name: !checks.${name}) (builtins.attrNames checks);
        in
        if failed == [ ] then
          true
        else
          builtins.trace ("failed checks: " + builtins.concatStringsSep ", " failed) false
      '

pass "FS-310-HDS-020-SDS-010-SMS-075 negative case 5: translationMode=none emits no DNAT for the tuple"
