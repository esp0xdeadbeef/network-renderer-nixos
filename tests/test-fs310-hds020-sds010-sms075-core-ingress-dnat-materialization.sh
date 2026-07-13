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
              controlPlane = { data = { }; };
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
