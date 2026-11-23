#!/usr/bin/env bash
# GAMP-ID: FS-310-HDS-010-SDS-010-SMS-130
# GAMP-SCOPE: software-module-test
set -euo pipefail

repo_root="${SMS_TEST_REPO_ROOT:-$(git -C "$(dirname "${BASH_SOURCE[0]}")" rev-parse --show-toplevel)}"

echo "--- FS-310-HDS-010-SDS-010-SMS-130: NixOS no policy-route invention ---"

policy_dir="${repo_root}/s88/ControlModule/render/container-networks/policy-routing"

echo "--- Source scan: no local table/priority arithmetic ---"
if rg -n '2000 \+|9000 \+ tableId|10000 \+ tableId|Priority = tableId' "${policy_dir}"; then
  echo "FAIL: NixOS policy routing still derives table IDs or rule priorities locally" >&2
  exit 1
fi
echo "PASS: no local route-table or rule-priority derivation remains"

# FS-310-HDS-020-SDS-010-SMS-060, second sentence: "The renderer shall not ...
# derive occurrence from interface topology". The scan above covers table and
# priority arithmetic; it does NOT cover the other way the same clause is
# broken, which is where a route is PLACED.
#
# Measured 2026-11-23: `routeOutputInterface` moves a route from the interface
# that declares it to whichever interface has the route's gateway as its p2p
# peer address (core peers 10.80.0.4, policy-dmz-wan peers 10.80.0.18, and the
# model's 10.90.10.0/24 on core has gateway 10.80.0.18 -- so core kept nothing).
# That is deriving occurrence from interface topology, by name, and it passed
# this test.
#
# The guard is deliberately narrow: it matches the peer-address match itself,
# not the word "topology", so ordinary comments and renames do not trip it.
echo "--- Source scan: no route placement by peer-address match ---"
if rg -n 'interfacePeerForFamily[^\n]*==[^\n]*gateway' \
     "${policy_dir}/route-helpers.nix" 2>/dev/null; then
  echo "FAIL: a route's interface is being chosen by matching its gateway against a peer address" >&2
  echo "      That is 'derive occurrence from interface topology' (FS-310-HDS-020-SDS-010-SMS-060)." >&2
  echo "      A route belongs on the interface its canonical record names." >&2
  exit 1
fi
echo "PASS: no route is placed by matching its gateway against an interface peer address"

positive_json="$(mktemp)"
missing_out="$(mktemp)"
missing_err="$(mktemp)"
trap 'rm -f "${positive_json}" "${missing_out}" "${missing_err}"' EXIT

echo "--- Positive: explicit CPM allocation is materialized ---"
env REPO_ROOT="${repo_root}" nix eval \
  --extra-experimental-features 'nix-command flakes' \
  --impure --json --expr '
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
        isAccessHostInterface = _: false;
        isDownstreamSelectorAccessInterface = _: false;
        laneAccessForRenderedName = _: null;
        hasAcceptForwardingRule = _: _: false;
        sourceReachabilityRoutes = {
          routeFor = _: _: null;
          matchesInterfaceOrigin = _: _: false;
        };
        sourcePrefixes = {
          forInterface = _: {
            staticPrefixes = [ ];
            sourceFiles = [ "/run/fs310-sms130-prefixes.json" ];
          };
        };
        forwardingSourceScope = {
          forSourceInterface = _: emptyScope;
          forPair = _: _: emptyScope;
        };
        ruleSourceScope = {
          forInterface = _: _: emptyScope;
        };
        routesByOutputInterface = { interfaceName, rawRoutesForPolicyTable, tableId, sourceIfNames }: { };
        rawRoutesForPolicyTable = _: _: _: [ ];
        serviceDnsRoutes = { prefer = routes: routes; };
        policyRoutingAllocations = {
          tenant = {
            source = "control-plane-model";
            allocation = "sms-130-construction";
            tableId = 2200;
            priority = 5000;
            tableRulePriority = 5001;
            dynamicRulePriority = 5002;
            mainSuppressPriority = 5003;
          };
        };
        forTarget = _: [ "tenant" ];
        forTargetRules = _: [ "tenant" ];
      };
      rules = aggregate.rules.tenant or [ ];
      dynamicRules = aggregate.dynamicSourceRules or [ ];
      firstMatching = pred: list:
        let matches = builtins.filter pred list;
        in if matches == [ ] then null else builtins.head matches;
      tableRule = firstMatching (rule: (rule.Table or null) == 2200) rules;
      mainRule = firstMatching (rule: (rule.Table or null) == 254) rules;
      dynamicTableRule = firstMatching (rule: (rule.table or null) == 2200) dynamicRules;
      dynamicMainRule = firstMatching (rule: (rule.table or null) == 254) dynamicRules;
    in
      {
        table = tableRule.Table;
        tablePriority = tableRule.Priority;
        mainPriority = mainRule.Priority;
        dynamicTable = dynamicTableRule.table;
        dynamicPriority = dynamicTableRule.priority;
        dynamicMainPriority = dynamicMainRule.priority;
      }
  ' >"${positive_json}"

if ! jq -e '
  .table == 2200
  and .tablePriority == 5001
  and .mainPriority == 5003
  and .dynamicTable == 2200
  and .dynamicPriority == 5002
  and .dynamicMainPriority == 5003
' "${positive_json}" >/dev/null; then
  echo "FAIL: explicit policyRoutingAllocation values were not materialized" >&2
  cat "${positive_json}" >&2
  exit 1
fi
echo "PASS: explicit table and priority allocation values are materialized"

echo "--- Seeded negative: missing allocation fails closed ---"
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
        isAccessHostInterface = _: false;
        isDownstreamSelectorAccessInterface = _: false;
        laneAccessForRenderedName = _: null;
        hasAcceptForwardingRule = _: _: false;
        sourceReachabilityRoutes = {
          routeFor = _: _: null;
          matchesInterfaceOrigin = _: _: false;
        };
        sourcePrefixes = { forInterface = _: emptyScope; };
        forwardingSourceScope = {
          forSourceInterface = _: emptyScope;
          forPair = _: _: emptyScope;
        };
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
  ' >"${missing_out}" 2>"${missing_err}"; then
  echo "FAIL: renderer accepted policy routing without policyRoutingAllocation" >&2
  cat "${missing_out}" >&2
  exit 1
fi

if ! grep -q 'policyRoutingAllocation' "${missing_err}"; then
  echo "FAIL: missing-allocation diagnostic did not name policyRoutingAllocation" >&2
  cat "${missing_err}" >&2
  exit 1
fi
echo "PASS: missing policyRoutingAllocation is rejected"

echo "PASS FS-310-HDS-010-SDS-010-SMS-130 NixOS no policy-route invention"
