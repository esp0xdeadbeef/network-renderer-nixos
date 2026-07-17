#!/usr/bin/env bash
# GAMP-ID: FS-310-HDS-020-SDS-010-SMS-075
# GAMP-SCOPE: software-module-test
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${repo_root}/tests/lib/test-common.sh"

nix_eval_true_or_fail "FS-310-HDS-020-SDS-010-SMS-075 native CPM public ingress materialization" \
  env REPO_ROOT="${repo_root}" \
    nix eval --impure --expr '
      let
        repoRoot = builtins.getEnv "REPO_ROOT";
        flake = builtins.getFlake ("path:" + repoRoot);
        lib = flake.inputs.nixpkgs.lib;
        coreCommon = import (repoRoot + "/s88/ControlModule/firewall/policy/core/common.nix") { inherit lib; };
        lookupCommon = import (repoRoot + "/s88/ControlModule/firewall/lookup/forwarding-intent/common.nix") { inherit lib; };
        relationName = "allow-wan-to-nebula";
        nativeRecord = {
          relationId = relationName;
          ingressInterface = "ppp0";
          returnBehavior = "stateful-return";
          sourcePreservation = "rewritten";
          translationMode = "napt";
          destinationTranslation = true;
          target = {
            service = "nebula";
            address = "192.0.2.10";
            port = 4242;
          };
          internalPath.egressInterface = "ens3";
          sourceTranslation = {
            mode = "snat";
            address = "10.19.0.3";
          };
          tupleRecords = [
            { protocol = "udp"; publicPort = 4242; targetPort = 4242; }
            { protocol = "tcp"; publicPort = 4242; targetPort = 4242; }
          ];
        };
        serviceNat = import (repoRoot + "/s88/ControlModule/firewall/policy/core/service-nat.nix") {
          inherit lib;
          common = coreCommon;
          natIntent.publicIngress = [ nativeRecord ];
          interfaceSet = { wanEntries = [ ]; wanNames = [ ]; };
          catalog = {
            trafficTypeDefinitions = { };
            serviceDefinitions = { };
            inventoryEndpoints = { };
            allowRelations = [ ];
          };
        };
        renderedNat = import (repoRoot + "/s88/ControlModule/firewall/policy/core/render-nat.nix") {
          inherit lib serviceNat;
          inherit (coreCommon) relationNameOf;
        };
        renderRuleset = import (repoRoot + "/s88/ControlModule/firewall/emission/render-ruleset.nix") { inherit lib; };
        coreRuleset = renderRuleset {
          forwardRules = renderedNat.portForwardForwardRules;
          natPreroutingRules4 = renderedNat.natPreroutingRules4;
          natPostroutingRules4 = renderedNat.natPostroutingRules4;
        };

        cpmForwardRule = {
          action = "accept";
          relationId = relationName;
          fromInterface = "policy-dmz";
          toInterface = "access-dmz";
          trafficType = "public-ingress";
          matches = [
            { family = "ipv4"; proto = "udp"; dports = [ 4242 ]; }
            { family = "ipv4"; proto = "tcp"; dports = [ 4242 ]; }
          ];
          destinationPrefixes = [ { family = 4; prefix = "192.0.2.10/32"; } ];
        };
        normalizedPairs = import (repoRoot + "/s88/ControlModule/firewall/lookup/forwarding-intent/explicit-pairs.nix") {
          inherit lib;
          common = lookupCommon;
          resolveInterfaceTokens = values: lookupCommon.asList values;
          runtimeTarget = { };
          nodeForwarding = {
            mode = "explicit-selector-forwarding";
            rules = [ cpmForwardRule ];
          };
        };
        explicitRules = import (repoRoot + "/s88/ControlModule/firewall/policy/explicit-forwarding.nix") {
          inherit lib;
          escapeComment = value: value;
          forwardingIntent.normalizedExplicitForwardPairs = normalizedPairs;
        };
        transitRuleset = renderRuleset { forwardRules = explicitRules; };

        noTranslationNat = import (repoRoot + "/s88/ControlModule/firewall/policy/core/service-nat.nix") {
          inherit lib;
          common = coreCommon;
          natIntent.publicIngress = [ (nativeRecord // {
            translationMode = "none";
            destinationTranslation = false;
          }) ];
          interfaceSet = { wanEntries = [ ]; wanNames = [ ]; };
          catalog = {
            trafficTypeDefinitions = { };
            serviceDefinitions = { };
            inventoryEndpoints = { };
            allowRelations = [ ];
          };
        };

        checks = {
          twoNativeTuples = builtins.length serviceNat.serviceNatEntries == 2;
          udpDnat = lib.hasInfix "iifname \"ppp0\" meta l4proto udp udp dport 4242 dnat to 192.0.2.10:4242" coreRuleset;
          tcpDnat = lib.hasInfix "iifname \"ppp0\" meta l4proto tcp tcp dport 4242 dnat to 192.0.2.10:4242" coreRuleset;
          exactCoreForward =
            lib.hasInfix "iifname \"ppp0\" oifname \"ens3\" ct status dnat meta nfproto ipv4 ip daddr 192.0.2.10 meta l4proto udp udp dport 4242 accept" coreRuleset
            && lib.hasInfix "iifname \"ppp0\" oifname \"ens3\" ct status dnat meta nfproto ipv4 ip daddr 192.0.2.10 meta l4proto tcp tcp dport 4242 accept" coreRuleset;
          exactSourceRewrite =
            lib.hasInfix "oifname \"ens3\" ip daddr 192.0.2.10 meta l4proto udp udp dport 4242 snat to 10.19.0.3" coreRuleset
            && lib.hasInfix "oifname \"ens3\" ip daddr 192.0.2.10 meta l4proto tcp tcp dport 4242 snat to 10.19.0.3" coreRuleset;
          postDnatPathScoped =
            lib.hasInfix "iifname \"policy-dmz\" oifname \"access-dmz\" ip daddr 192.0.2.10/32 meta nfproto ipv4 meta l4proto udp udp dport { 4242 } accept" transitRuleset
            && lib.hasInfix "iifname \"policy-dmz\" oifname \"access-dmz\" ip daddr 192.0.2.10/32 meta nfproto ipv4 meta l4proto tcp tcp dport { 4242 } accept" transitRuleset;
          noBroadPostDnatAccept = !lib.hasInfix "iifname \"policy-dmz\" oifname \"access-dmz\" accept" transitRuleset;
          noPublicAddressLiteralRequired = !lib.hasInfix "198.51.100." coreRuleset;
          translationNoneEmitsNothing = noTranslationNat.serviceNatEntries == [ ];
        };
        failed = builtins.filter (name: !checks.${name}) (builtins.attrNames checks);
      in
      if failed == [ ] then true
      else builtins.trace ("failed checks: " + builtins.concatStringsSep ", " failed) false
    '

pass "FS-310-HDS-020-SDS-010-SMS-075: renderer consumes native CPM NAT/forwarding authority without a public-address literal"

stderr_file="$(mktemp)"
trap 'rm -f "${stderr_file}"' EXIT
set +e
REPO_ROOT="${repo_root}" nix eval --impure --expr '
  let
    repoRoot = builtins.getEnv "REPO_ROOT";
    flake = builtins.getFlake ("path:" + repoRoot);
    lib = flake.inputs.nixpkgs.lib;
    common = import (repoRoot + "/s88/ControlModule/firewall/policy/core/common.nix") { inherit lib; };
  in
  (import (repoRoot + "/s88/ControlModule/firewall/policy/core/service-nat.nix") {
    inherit lib common;
    interfaceSet = { wanEntries = [ ]; wanNames = [ ]; };
    catalog = {
      trafficTypeDefinitions = { };
      serviceDefinitions = { };
      inventoryEndpoints = { };
      allowRelations = [ ];
    };
    natIntent.publicIngress = [ {
      relationId = "incomplete-public-ingress";
      ingressInterface = "ppp0";
      destinationTranslation = true;
      translationMode = "napt";
      target.address = "192.0.2.10";
      tupleRecords = [ ];
    } ];
  }).serviceNatEntries
' >/dev/null 2>"${stderr_file}"
status=$?
set -e

if [[ "${status}" -eq 0 ]] || ! grep -Fq "CPM public-ingress record is incomplete" "${stderr_file}"; then
  echo "FAIL FS-310-HDS-020-SDS-010-SMS-075: incomplete native authority did not fail closed" >&2
  cat "${stderr_file}" >&2
  exit 1
fi

pass "FS-310-HDS-020-SDS-010-SMS-075: incomplete native CPM authority fails closed"
