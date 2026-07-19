#!/usr/bin/env bash
set -euo pipefail
# GAMP-ID: FS-230-HDS-010-SDS-010-SMS-040
# GAMP-SCOPE: software-module-test

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${repo_root}/tests/lib/test-common.sh"

result="$({ REPO_ROOT="${repo_root}" nix eval --impure --json --expr '
  let
    root = builtins.getEnv "REPO_ROOT";
    flake = builtins.getFlake ("path:" + root);
    lib = flake.inputs.nixpkgs.lib;
    common = import (root + "/s88/ControlModule/firewall/lookup/forwarding-intent/common.nix") { inherit lib; };
    runtimeDestination = {
      sourceClass = "protected";
      source = "intent-routed-prefix";
      sourceFile = "/run/secrets/lab-dmz-ipv6-prefix";
      prefixName = "dmz-public";
      interfaceIdentifier = "0:0:0:0:0:0:0:4242";
      delegatedPrefixLength = 48;
      perTenantPrefixLength = 64;
      slot = 2;
      targetPrefixLength = 128;
    };
    rule = {
      action = "accept";
      relationId = "allow-wan-to-nebula-ipv6";
      fromInterface = "ppp0";
      toInterface = "core";
      trafficType = "public-ingress";
      matches = [ { family = "ipv6"; proto = "udp"; dports = [ 4242 ]; } ];
      destinationPrefixes = [ ];
      destinationRuntimeAddresses = [ runtimeDestination ];
    };
    normalize = candidate:
      import (root + "/s88/ControlModule/firewall/lookup/forwarding-intent/explicit-pairs.nix") {
        inherit lib common;
        resolveInterfaceTokens = values: common.asList values;
        runtimeTarget = { };
        nodeForwarding = {
          mode = "explicit-core-forwarding";
          rules = [ candidate ];
        };
      };
    pairs = normalize rule;
    renderRuleset = import (root + "/s88/ControlModule/firewall/emission/render-ruleset.nix") { inherit lib; };
    ruleset = renderRuleset { forwardPairs = pairs; };
    explicitRules = import (root + "/s88/ControlModule/firewall/policy/explicit-forwarding.nix") {
      inherit lib;
      escapeComment = value: value;
      forwardingIntent.normalizedExplicitForwardPairs = pairs;
    };
    explicitRuleset = renderRuleset { forwardRules = explicitRules; };
    candidatesFor = values:
      import (root + "/s88/ControlModule/render/container-networks/runtime-destination-forwarding.nix") {
        inherit lib;
        pairs = values;
      };
    candidates = candidatesFor pairs;
    candidate = builtins.head candidates;
    pkgs = flake.inputs.nixpkgs.legacyPackages.${builtins.currentSystem};
    runtimeModule = import (root + "/s88/ControlModule/render/containers/module/dynamic-destination-forwarding.nix") {
      inherit lib pkgs;
      dynamicDestinationForwardRules = candidates;
    };
    service = runtimeModule.config.systemd.services.s88-runtime-destination-forward-0;
    path = runtimeModule.config.systemd.paths.s88-runtime-destination-forward-0;
    missingSource = builtins.tryEval (builtins.deepSeq (candidatesFor (normalize (rule // {
      destinationRuntimeAddresses = [ (builtins.removeAttrs runtimeDestination [ "sourceFile" ]) ];
    }))) true);
    staticConflict = builtins.tryEval (builtins.deepSeq (renderRuleset {
      forwardPairs = normalize (rule // {
        destinationPrefixes = [ { family = 6; prefix = "2001:db8:230:2::4242/128"; } ];
      });
    }) true);
  in {
    preserved = (builtins.head pairs).destinationRuntimeAddresses == [ runtimeDestination ];
    failClosedPlaceholder = lib.hasInfix
      "ip6 daddr ::/128 meta nfproto ipv6 meta l4proto udp udp dport { 4242 } accept comment \"allow-wan-to-nebula-ipv6\""
      ruleset
      && lib.hasInfix
        "ip6 daddr ::/128 meta nfproto ipv6 meta l4proto udp udp dport { 4242 } accept comment \"allow-wan-to-nebula-ipv6\""
        explicitRuleset;
    noBroadTuple =
      !(lib.hasInfix "oifname \"core\" meta nfproto ipv6 meta l4proto udp" ruleset)
      && !(lib.hasInfix "oifname \"core\" meta nfproto ipv6 meta l4proto udp" explicitRuleset);
    noPublicLiteral = !(lib.hasInfix "2001:db8:230" (ruleset + explicitRuleset));
    exactCandidate = candidate == {
      sourceFile = runtimeDestination.sourceFile;
      interfaceIdentifier = runtimeDestination.interfaceIdentifier;
      delegatedPrefixLength = 48;
      perTenantPrefixLength = 64;
      slot = 2;
      targetPrefixLength = 128;
      inIf = "ppp0";
      outIf = "core";
      protocol = "udp";
      destinationPort = 4242;
      action = "accept";
      comment = "allow-wan-to-nebula-ipv6";
    };
    runtimeServiceWired =
      service.after == [ "nftables.service" ]
      && service.partOf == [ "nftables.service" ]
      && service.serviceConfig.Type == "oneshot"
      && path.pathConfig.PathExists == runtimeDestination.sourceFile
      && path.pathConfig.PathChanged == runtimeDestination.sourceFile;
    missingSourceRejected = missingSource.success == false;
    staticConflictRejected = staticConflict.success == false;
  }
'; })"

jq -e 'all(.[]; . == true)' <<<"${result}" >/dev/null || {
  printf 'FAIL FS-230-HDS-010-SDS-010-SMS-040: NixOS renderer contract mismatch\n%s\n' "${result}" >&2
  exit 1
}

helper="${repo_root}/s88/ControlModule/render/containers/module/runtime-delegated-prefix.py"
tmp_dir="$(mktemp -d)"
trap 'rm -rf "${tmp_dir}"' EXIT
source_file="${tmp_dir}/prefix"
printf '%s\n' '2001:db8:230::/48' >"${source_file}"

derived="$(${helper} \
  --source "${source_file}" \
  --family 6 \
  --delegated-prefix-length 48 \
  --tenant-prefix-length 64 \
  --slot 2 \
  --interface-identifier '::4242')"
test "${derived}" = '2001:db8:230:2::4242/128' || {
  printf 'FAIL FS-230-HDS-010-SDS-010-SMS-040: wrong runtime /128 derivation\n' >&2
  exit 1
}

printf '%s\n' '2001:db8:230::/56' >"${source_file}"
if "${helper}" \
  --source "${source_file}" \
  --family 6 \
  --delegated-prefix-length 48 \
  --tenant-prefix-length 64 \
  --slot 2 \
  --interface-identifier '::4242' >"${tmp_dir}/stdout" 2>"${tmp_dir}/stderr"; then
  printf 'FAIL FS-230-HDS-010-SDS-010-SMS-040: invalid protected source accepted\n' >&2
  exit 1
fi
test ! -s "${tmp_dir}/stdout"
if grep -q '2001:db8' "${tmp_dir}/stderr"; then
  printf 'FAIL FS-230-HDS-010-SDS-010-SMS-040: protected address leaked in diagnostic\n' >&2
  exit 1
fi

printf 'PASS FS-230-HDS-010-SDS-010-SMS-040 protected Nebula IPv6 ingress NixOS rendering\n'
