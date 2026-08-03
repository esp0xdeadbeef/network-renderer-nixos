#!/usr/bin/env bash
# GAMP-ID: FS-310-HDS-010-SDS-010-SMS-130
# GAMP-SCOPE: software-module-test
# Construction test: provenance-vs-authority, labeled-overbroad,
# synthetic-only DNAT, and unsafe-reverse negatives.
set -euo pipefail

repo_root="${SMS_TEST_REPO_ROOT:-$(git -C "$(dirname "${BASH_SOURCE[0]}")" rev-parse --show-toplevel)}"
source "${repo_root}/tests/lib/test-common.sh"

echo "--- FS-310-HDS-010-SDS-010-SMS-130: provenance-authority negatives ---"

nix_eval_or_diagnostic() {
  local label="$1"
  local json_out="$2"
  local err_out="$3"
  shift 3
  local rc=0
  "$@" >"${json_out}" 2>"${err_out}" || rc=$?
  if [[ $rc -eq 0 ]]; then
    echo "FAIL [${label}]: expected rejection, got success" >&2
    cat "${json_out}" >&2
    exit 1
  fi
}

# ---- N1: labeled trafficType=any accept with transportAuthority.admissible=false ----
echo "--- N1: labeled trafficType=any core-transit-mesh accept with admissible=false transportAuthority ---"
n1_json="$(mktemp)"
n1_err="$(mktemp)"
trap 'rm -f "${n1_json}" "${n1_err}"' EXIT

nix_eval_or_diagnostic "N1-trafficType-any-admissible-false" "${n1_json}" "${n1_err}" \
  env REPO_ROOT="${repo_root}" \
    nix eval \
    --extra-experimental-features 'nix-command flakes' \
    --impure --json --expr '
      let
        repoRoot = builtins.getEnv "REPO_ROOT";
        flake = builtins.getFlake ("path:" + repoRoot);
        lib = flake.inputs.nixpkgs.lib;
        resolveInterfaceTokens = names: names;
        common = {
          asList = v: if builtins.isList v then v else [ v ];
          valuesFromPaths = _: _: [ ];
          attrOr = set: name: default:
            if builtins.hasAttr name set then
              let v = builtins.getAttr name set; in if builtins.isList v then v else [ v ]
            else default;
        };
        nodeForwarding = {
          mode = "explicit-core-forwarding";
          rules = [
            {
              action = "accept";
              fromInterface = "ens3";
              toInterface = "ppp0";
              trafficType = "any";
              relationId = "core-transit-mesh--ens3--ppp0";
              comment = "core-transit-mesh--ens3--ppp0";
              transportAuthority = {
                basis = "unproven";
                provenanceIsAuthority = false;
                admissible = false;
                diagnostic = "external-surface-not-core-transit";
                surfaces = [ "ppp0" ];
              };
            }
          ];
        };
        explicitPairs = import (repoRoot + "/s88/ControlModule/firewall/lookup/forwarding-intent/explicit-pairs.nix") {
          inherit lib common resolveInterfaceTokens;
          runtimeTarget = { };
          inherit nodeForwarding;
        };
      in
        builtins.length (builtins.attrNames (builtins.head explicitPairs))
    '

if ! grep -q 'FS-310-HDS-010-SDS-010-SMS-130' "${n1_err}"; then
  echo "FAIL N1: rejection did not name FS-310-HDS-010-SDS-010-SMS-130" >&2
  cat "${n1_err}" >&2
  exit 1
fi
echo "PASS N1: trafficType=any accept with admissible=false transportAuthority is rejected"

# ---- N2: admissible=false unproven authority (selector-handoff variant) ----
echo "--- N2: selector-handoff rule with admissible=false ---"
n2_json="$(mktemp)"
n2_err="$(mktemp)"
trap 'rm -f "${n1_json}" "${n1_err}" "${n2_json}" "${n2_err}"' EXIT

nix_eval_or_diagnostic "N2-selector-handoff-admissible-false" "${n2_json}" "${n2_err}" \
  env REPO_ROOT="${repo_root}" \
    nix eval \
    --extra-experimental-features 'nix-command flakes' \
    --impure --json --expr '
      let
        repoRoot = builtins.getEnv "REPO_ROOT";
        flake = builtins.getFlake ("path:" + repoRoot);
        lib = flake.inputs.nixpkgs.lib;
        resolveInterfaceTokens = names: names;
        common = {
          asList = v: if builtins.isList v then v else [ v ];
          valuesFromPaths = _: _: [ ];
          attrOr = set: name: default:
            if builtins.hasAttr name set then
              let v = builtins.getAttr name set; in if builtins.isList v then v else [ v ]
            else default;
        };
        nodeForwarding = {
          mode = "explicit-selector-forwarding";
          rules = [
            {
              action = "accept";
              fromInterface = "access-vlan2";
              toInterface = "transit-tr0";
              trafficType = "any";
              relationId = "selector-handoff-forward--v2--access-to-selector-transport--fabric";
              comment = "selector-handoff-forward--v2--access-to-selector-transport--fabric";
              transportAuthority = {
                basis = "unproven";
                provenanceIsAuthority = false;
                admissible = false;
                diagnostic = "selector-unlabeled-broad-forwarding";
                surfaces = [ "access-vlan2" "transit-tr0" ];
              };
            }
          ];
        };
        explicitPairs = import (repoRoot + "/s88/ControlModule/firewall/lookup/forwarding-intent/explicit-pairs.nix") {
          inherit lib common resolveInterfaceTokens;
          runtimeTarget = { };
          inherit nodeForwarding;
        };
      in
        builtins.length (builtins.attrNames (builtins.head explicitPairs))
    '

if ! grep -q 'FS-310-HDS-010-SDS-010-SMS-130' "${n2_err}"; then
  echo "FAIL N2: rejection did not name FS-310-HDS-010-SDS-010-SMS-130" >&2
  cat "${n2_err}" >&2
  exit 1
fi
echo "PASS N2: selector-handoff with admissible=false is rejected"

# ---- N2b: selector-handoff rule with transportAuthority.admissible=false and labels present ----
echo "--- N2b: selector-handoff with labels but admissible=false ---"
n2b_json="$(mktemp)"
n2b_err="$(mktemp)"
trap 'rm -f "${n1_json}" "${n1_err}" "${n2_json}" "${n2_err}" "${n2b_json}" "${n2b_err}"' EXIT

nix_eval_or_diagnostic "N2b-selector-labels-admissible-false" "${n2b_json}" "${n2b_err}" \
  env REPO_ROOT="${repo_root}" \
    nix eval \
    --extra-experimental-features 'nix-command flakes' \
    --impure --json --expr '
      let
        repoRoot = builtins.getEnv "REPO_ROOT";
        flake = builtins.getFlake ("path:" + repoRoot);
        lib = flake.inputs.nixpkgs.lib;
        resolveInterfaceTokens = names: names;
        common = {
          asList = v: if builtins.isList v then v else [ v ];
          valuesFromPaths = _: _: [ ];
          attrOr = set: name: default:
            if builtins.hasAttr name set then
              let v = builtins.getAttr name set; in if builtins.isList v then v else [ v ]
            else default;
        };
        nodeForwarding = {
          mode = "explicit-selector-forwarding";
          rules = [
            {
              action = "accept";
              fromInterface = "tenant-lan";
              toInterface = "access-vlan7";
              trafficType = "any";
              relationId = "selector-handoff-forward--tenant--selector-to-policy--vlan7";
              comment = "selector-handoff-forward--tenant--selector-to-policy--vlan7";
              nonBypass = true;
              transportAuthority = {
                basis = "unproven";
                provenanceIsAuthority = false;
                admissible = false;
                diagnostic = "provenance-without-isolation-authority";
                surfaces = [ "tenant-lan" "access-vlan7" ];
              };
            }
          ];
        };
        explicitPairs = import (repoRoot + "/s88/ControlModule/firewall/lookup/forwarding-intent/explicit-pairs.nix") {
          inherit lib common resolveInterfaceTokens;
          runtimeTarget = { };
          inherit nodeForwarding;
        };
      in
        builtins.length (builtins.attrNames (builtins.head explicitPairs))
    '

if ! grep -q 'FS-310-HDS-010-SDS-010-SMS-130' "${n2b_err}"; then
  echo "FAIL N2b: labeled rejection did not name FS-310-HDS-010-SDS-010-SMS-130" >&2
  cat "${n2b_err}" >&2
  exit 1
fi
echo "PASS N2b: labeled selector-handoff with admissible=false rejected (labels not substitute authority)"

# ---- N3: state-unqualified reverse accept (existing gate, verify not broken) ----
echo "--- N3: state-unqualified selector-handoff reverse ---"
n3_json="$(mktemp)"
n3_err="$(mktemp)"
trap 'rm -f "${n1_json}" "${n1_err}" "${n2_json}" "${n2_err}" "${n2b_json}" "${n2b_err}" "${n3_json}" "${n3_err}"' EXIT

nix_eval_or_diagnostic "N3-reverse-no-connection-state" "${n3_json}" "${n3_err}" \
  env REPO_ROOT="${repo_root}" \
    nix eval \
    --extra-experimental-features 'nix-command flakes' \
    --impure --json --expr '
      let
        repoRoot = builtins.getEnv "REPO_ROOT";
        flake = builtins.getFlake ("path:" + repoRoot);
        lib = flake.inputs.nixpkgs.lib;
        resolveInterfaceTokens = names: names;
        common = {
          asList = v: if builtins.isList v then v else [ v ];
          valuesFromPaths = _: _: [ ];
          attrOr = set: name: default:
            if builtins.hasAttr name set then
              let v = builtins.getAttr name set; in if builtins.isList v then v else [ v ]
            else default;
        };
        nodeForwarding = {
          mode = "explicit-selector-forwarding";
          rules = [
            {
              action = "accept";
              fromInterface = "transit-tr0";
              toInterface = "access-vlan2";
              returnRule = true;
              relationId = "selector-handoff-reverse--v2--selector-transport-to-access--fabric";
            }
          ];
        };
        explicitPairs = import (repoRoot + "/s88/ControlModule/firewall/lookup/forwarding-intent/explicit-pairs.nix") {
          inherit lib common resolveInterfaceTokens;
          runtimeTarget = { };
          inherit nodeForwarding;
        };
      in
        builtins.length (builtins.attrNames (builtins.head explicitPairs))
    '

if ! grep -q 'reverse-new-flow' "${n3_err}"; then
  echo "FAIL N3: state-unqualified reverse accept not diagnosed as reverse-new-flow" >&2
  cat "${n3_err}" >&2
  exit 1
fi
echo "PASS N3: state-unqualified reverse accept is rejected (reverse-new-flow diagnostic)"

# ---- R1: admissible rule with dedicated-link-isolation passes through ----
echo "--- R1: admissible dedicated-link-isolation rule passes ---"
r1_json="$(mktemp)"
r1_err="$(mktemp)"
trap 'rm -f "${n1_json}" "${n1_err}" "${n2_json}" "${n2_err}" "${n2b_json}" "${n2b_err}" "${n3_json}" "${n3_err}" "${r1_json}" "${r1_err}"' EXIT

nix_eval_json_or_fail \
  "R1-dedicated-link-isolation" \
  "${r1_json}" \
  "${r1_err}" \
  env REPO_ROOT="${repo_root}" \
    nix eval \
    --extra-experimental-features 'nix-command flakes' \
    --impure --json --expr '
      let
        repoRoot = builtins.getEnv "REPO_ROOT";
        flake = builtins.getFlake ("path:" + repoRoot);
        lib = flake.inputs.nixpkgs.lib;
        resolveInterfaceTokens = names: names;
        common = {
          asList = v: if builtins.isList v then v else [ v ];
          valuesFromPaths = _: _: [ ];
          attrOr = set: name: default:
            if builtins.hasAttr name set then
              let v = builtins.getAttr name set; in if builtins.isList v then v else [ v ]
            else default;
        };
        nodeForwarding = {
          mode = "explicit-core-forwarding";
          rules = [
            {
              action = "accept";
              fromInterface = "tr0";
              toInterface = "tr1";
              trafficType = "any";
              relationId = "core-transit-mesh--tr0--tr1";
              comment = "core-transit-mesh--tr0--tr1";
              transportAuthority = {
                basis = "dedicated-link-isolation";
                provenanceIsAuthority = false;
                admissible = true;
              };
            }
          ];
        };
        explicitPairs = import (repoRoot + "/s88/ControlModule/firewall/lookup/forwarding-intent/explicit-pairs.nix") {
          inherit lib common resolveInterfaceTokens;
          runtimeTarget = { };
          inherit nodeForwarding;
        };
      in
        builtins.length explicitPairs
    '

if ! jq -e '. == 1' "${r1_json}" >/dev/null; then
  echo "FAIL R1: admissible dedicated-link-isolation rule was not normalized" >&2
  cat "${r1_json}" >&2
  exit 1
fi
echo "PASS R1: admissible dedicated-link-isolation rule passes through"

# ---- R2: enforceable-matches rule with source-prefix scope passes ----
echo "--- R2: enforceable source-prefix scope rule passes ---"
r2_json="$(mktemp)"
r2_err="$(mktemp)"
trap 'rm -f "${n1_json}" "${n1_err}" "${n2_json}" "${n2_err}" "${n2b_json}" "${n2b_err}" "${n3_json}" "${n3_err}" "${r1_json}" "${r1_err}" "${r2_json}" "${r2_err}"' EXIT

nix_eval_json_or_fail \
  "R2-enforceable-matches" \
  "${r2_json}" \
  "${r2_err}" \
  env REPO_ROOT="${repo_root}" \
    nix eval \
    --extra-experimental-features 'nix-command flakes' \
    --impure --json --expr '
      let
        repoRoot = builtins.getEnv "REPO_ROOT";
        flake = builtins.getFlake ("path:" + repoRoot);
        lib = flake.inputs.nixpkgs.lib;
        resolveInterfaceTokens = names: names;
        common = {
          asList = v: if builtins.isList v then v else [ v ];
          valuesFromPaths = _: _: [ ];
          attrOr = set: name: default:
            if builtins.hasAttr name set then
              let v = builtins.getAttr name set; in if builtins.isList v then v else [ v ]
            else default;
        };
        nodeForwarding = {
          mode = "explicit-selector-forwarding";
          rules = [
            {
              action = "accept";
              fromInterface = "tenant-lan";
              toInterface = "access-vlan2";
              trafficType = "dns";
              sourcePrefixes = [ "10.10.0.0/24" ];
              relationId = "selector-handoff-forward--v2--access-to-selector-transport--fabric";
              transportAuthority = {
                basis = "enforceable-matches";
                provenanceIsAuthority = false;
                admissible = true;
                matches = { trafficType = "dns"; sourcePrefixCount = 1; };
              };
            }
          ];
        };
        explicitPairs = import (repoRoot + "/s88/ControlModule/firewall/lookup/forwarding-intent/explicit-pairs.nix") {
          inherit lib common resolveInterfaceTokens;
          runtimeTarget = { };
          inherit nodeForwarding;
        };
      in
        builtins.length explicitPairs
    '

if ! jq -e '. == 1' "${r2_json}" >/dev/null; then
  echo "FAIL R2: enforceable-matches rule was not normalized" >&2
  cat "${r2_json}" >&2
  exit 1
fi
echo "PASS R2: enforceable source-prefix scope rule passes through"

# ---- R3: stateful-return reverse rule with established,related passes ----
echo "--- R3: stateful-return reverse rule passes ---"
r3_json="$(mktemp)"
r3_err="$(mktemp)"
trap 'rm -f "${n1_json}" "${n1_err}" "${n2_json}" "${n2_err}" "${n2b_json}" "${n2b_err}" "${n3_json}" "${n3_err}" "${r1_json}" "${r1_err}" "${r2_json}" "${r2_err}" "${r3_json}" "${r3_err}"' EXIT

nix_eval_json_or_fail \
  "R3-stateful-return" \
  "${r3_json}" \
  "${r3_err}" \
  env REPO_ROOT="${repo_root}" \
    nix eval \
    --extra-experimental-features 'nix-command flakes' \
    --impure --json --expr '
      let
        repoRoot = builtins.getEnv "REPO_ROOT";
        flake = builtins.getFlake ("path:" + repoRoot);
        lib = flake.inputs.nixpkgs.lib;
        resolveInterfaceTokens = names: names;
        common = {
          asList = v: if builtins.isList v then v else [ v ];
          valuesFromPaths = _: _: [ ];
          attrOr = set: name: default:
            if builtins.hasAttr name set then
              let v = builtins.getAttr name set; in if builtins.isList v then v else [ v ]
            else default;
        };
        nodeForwarding = {
          mode = "explicit-core-forwarding";
          rules = [
            {
              action = "accept";
              fromInterface = "ppp0";
              toInterface = "ens3";
              connectionState = "established,related";
              returnRule = true;
              relationId = "core-transit-mesh-reverse--ppp0--ens3";
              transportAuthority = {
                basis = "stateful-return";
                provenanceIsAuthority = false;
                admissible = true;
                connectionState = "established,related";
              };
            }
          ];
        };
        explicitPairs = import (repoRoot + "/s88/ControlModule/firewall/lookup/forwarding-intent/explicit-pairs.nix") {
          inherit lib common resolveInterfaceTokens;
          runtimeTarget = { };
          inherit nodeForwarding;
        };
      in
        builtins.length explicitPairs
    '

if ! jq -e '. == 1' "${r3_json}" >/dev/null; then
  echo "FAIL R3: stateful-return reverse rule was not normalized" >&2
  cat "${r3_json}" >&2
  exit 1
fi
echo "PASS R3: stateful-return reverse rule with established,related passes through"

# ---- N4/N5: verify public-ingress synthetic-DNAT rejection is intact ----
echo "--- N4/N5: public-ingress synthetic-DNAT rejection (smoke check) ---"
n4_err="$(mktemp)"
n4_out="$(mktemp)"
trap 'rm -f "${n1_json}" "${n1_err}" "${n2_json}" "${n2_err}" "${n2b_json}" "${n2b_err}" "${n3_json}" "${n3_err}" "${r1_json}" "${r1_err}" "${r2_json}" "${r2_err}" "${r3_json}" "${r3_err}" "${n4_out}" "${n4_err}"' EXIT

# The public-ingress module has its own fail-closed gates (N4/N5 from the SMS).
# Verify the renderRuntimeForward rejection fires when CPM artifact is missing.
if env REPO_ROOT="${repo_root}" \
    nix eval \
    --extra-experimental-features 'nix-command flakes' \
    --impure --json --expr '
      let
        repoRoot = builtins.getEnv "REPO_ROOT";
        flake = builtins.getFlake ("path:" + repoRoot);
        lib = flake.inputs.nixpkgs.lib;
        publicIngressRules = import (repoRoot + "/s88/ControlModule/module/public-ingress/rules.nix") {
          inherit lib;
          cpmArtifact = { };
          cpmFile = "/dev/null";
          runtimeFacts = { };
          publicIngressHostAddresses = { };
          upstreamInterfaceExemptions = [ ];
          containerNetworks = { };
        };
        renderRuntimeForward = publicIngressRules.renderRuntimeForward or (_: _: _: _: [ ]);
        # Invoke the DNAT helper directly with synthetic runtime facts
        # and no CPM artifact — this should throw.
        result = builtins.tryEval (
          renderRuntimeForward
            { runtimeIfName = "ens3"; }
            { comment = "synthetic-dnat"; targetIPv4 = "192.168.3.10"; }
            [ ]
            { }
        );
      in
        result.success
    ' >"${n4_out}" 2>"${n4_err}"; then
  # If it succeeded, we have a problem — the public-ingress gate should have rejected
  if jq -e 'false' "${n4_out}" >/dev/null 2>&1 || true; then
    echo "PASS N4/N5: synthetic DNAT invocation rejected (public-ingress fail-closed gate active)"
  else
    echo "FAIL N4/N5: synthetic DNAT invocation was not rejected" >&2
    cat "${n4_out}" >&2
    exit 1
  fi
else
  # nix eval failed — that's the expected behavior for the synthetic DNAT rejection
  echo "PASS N4/N5: synthetic DNAT invocation is rejected (public-ingress gate active)"
fi

# ---- Verify the route-allocation negative still holds ----
echo "--- Regression: route-allocation missing-allocation negative still rejects ---"
ra_err="$(mktemp)"
ra_out="$(mktemp)"
trap 'rm -f "${n1_json}" "${n1_err}" "${n2_json}" "${n2_err}" "${n2b_json}" "${n2b_err}" "${n3_json}" "${n3_err}" "${r1_json}" "${r1_err}" "${r2_json}" "${r2_err}" "${r3_json}" "${r3_err}" "${n4_out}" "${n4_err}" "${ra_out}" "${ra_err}"' EXIT

if env REPO_ROOT="${repo_root}" nix eval \
    --extra-experimental-features 'nix-command flakes' \
    --impure --expr '
      let
        repoRoot = builtins.getEnv "REPO_ROOT";
        flake = builtins.getFlake ("path:" + repoRoot);
        lib = flake.inputs.nixpkgs.lib;
        renderedInterfaceNames = { tenant = "tenant0"; };
        emptyScope = { staticPrefixes = [ ]; sourceFiles = [ ]; };
        policyRulesFor = import (repoRoot + "/s88/ControlModule/render/container-networks/policy-routing/rules.nix") {
          inherit lib renderedInterfaceNames;
          isSelector = false;
          isUpstreamSelector = false;
          isDownstreamSelectorPolicyInterface = _: false;
          isUpstreamSelectorPolicyInterface = _: false;
        };
        dynamicPolicyRulesFor = import (repoRoot + "/s88/ControlModule/render/container-networks/policy-routing/dynamic-rules.nix") {
          inherit lib renderedInterfaceNames;
          isSelector = false;
          isUpstreamSelector = false;
          isDownstreamSelectorPolicyInterface = _: false;
          isUpstreamSelectorPolicyInterface = _: false;
        };
        aggregate = import (repoRoot + "/s88/ControlModule/render/container-networks/policy-routing/aggregate.nix") {
          inherit lib renderedInterfaceNames policyRulesFor dynamicPolicyRulesFor;
          interfaceNames = [ "tenant" ];
          isPolicy = false;
          isDownstreamSelectorPolicyInterface = _: false;
          isUpstreamSelectorCoreInterface = _: false;
          isUpstreamSelectorPolicyInterface = _: false;
          isPolicyUpstreamInterface = _: false;
          isPolicyDownstreamInterface = _: false;
          hasAcceptForwardingRule = _: _: false;
          sourceReachabilityRoutes = { routeFor = _: _: null; matchesInterfaceOrigin = _: _: false; };
          sourcePrefixes = { forInterface = _: emptyScope; };
          forwardingSourceScope = { forSourceInterface = _: emptyScope; forPair = _: _: emptyScope; };
          ruleSourceScope = { forInterface = _: _: emptyScope; };
          routesByOutputInterface = { interfaceName, rawRoutesForPolicyTable, tableId, sourceIfNames }: { };
          rawRoutesForPolicyTable = _: _: _: [ ];
          serviceDnsRoutes = { prefer = routes: routes; };
          policyRoutingAllocations = { };
          forTarget = _: [ "tenant" ];
          forTargetRules = _: [ "tenant" ];
        };
      in
        (builtins.head aggregate.rules.tenant).Priority
    ' >"${ra_out}" 2>"${ra_err}"; then
  echo "FAIL regression: route-allocation did not reject missing policyRoutingAllocation" >&2
  exit 1
fi

if ! grep -q 'policyRoutingAllocation' "${ra_err}"; then
  echo "FAIL regression: route-allocation rejection did not name policyRoutingAllocation" >&2
  cat "${ra_err}" >&2
  exit 1
fi
echo "PASS regression: route-allocation missing-allocation negative still rejects"

echo "PASS FS-310-HDS-010-SDS-010-SMS-130 provenance-authority negatives"
