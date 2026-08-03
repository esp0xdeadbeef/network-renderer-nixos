#!/usr/bin/env bash
# GAMP-ID: FS-800-HDS-030-SDS-020-SMS-020
# GAMP-SCOPE: software-module-test
set -euo pipefail

repo_root="${SMS_TEST_REPO_ROOT:-$(git -C "$(dirname "${BASH_SOURCE[0]}")" rev-parse --show-toplevel)}"
source "${repo_root}/tests/lib/test-common.sh"

result="$(REPO_ROOT="${repo_root}" nix eval --impure --json --expr '
  let
    repoRoot = builtins.getEnv "REPO_ROOT";
    flake = builtins.getFlake ("path:" + repoRoot);
    lib = flake.inputs.nixpkgs.lib;
    system = builtins.currentSystem;
    pkgs = import flake.inputs.nixpkgs { inherit system; };
    ipv6 = {
      mode = "dhcpv6-pd";
      defaultRoute = true;
      iaid = 7;
      prefixDelegationRequestId = 11;
      duidMode = "persistent";
      resolverMode = "disabled";
      ipv4Mode = "disabled";
      routerSolicitation = false;
      fallbackPolicy = "none";
    };
    renderedModel = {
      unitName = "test-core";
      interfaces.provider-handoff.containerInterfaceName = "ens20";
      services.pppoe.client = {
        interface = "provider-handoff";
        runtimeInterface = "ppp-test";
        defaultRoute = true;
        usePeerDns = false;
        mtu = 1492;
        credentials = {
          usernameFile = "/run/secrets/test-username";
          passwordFile = "/run/secrets/test-password";
        };
        inherit ipv6;
      };
    };
    module = import (repoRoot + "/s88/ControlModule/render/containers/module/pppoe.nix") {
      inherit lib pkgs renderedModel;
    };
    evaluated = lib.nixosSystem {
      inherit system;
      modules = [ module.config ];
    };
    pppd = evaluated.config.systemd.services."pppd-s88-pppoe-client-provider-handoff";
    pd = evaluated.config.systemd.services."s88-pppoe-ipv6-pd-provider-handoff";
  in {
    pppdOptions = pppd.preStart;
    dhcpcdConfig = builtins.readFile evaluated.config.environment.etc."s88/pppoe-ipv6-provider-handoff.conf".source;
    pdAfter = pd.after;
    pdRequires = pd.requires;
    pdBindsTo = pd.bindsTo;
    pdPartOf = pd.partOf;
    pdExecStartPre = builtins.toString pd.serviceConfig.ExecStartPre;
    pdExecStart = builtins.toString pd.serviceConfig.ExecStart;
    pdRestart = pd.serviceConfig.Restart;
    firewall = evaluated.config.networking.nftables.ruleset;
  }
')"

jq -e '
  (.pppdOptions | contains("defaultroute6"))
  and (.dhcpcdConfig | contains("nohook resolv.conf"))
  and (.dhcpcdConfig | contains("noipv6rs"))
  and (.dhcpcdConfig | contains("noipv4"))
  and (.dhcpcdConfig | contains("ipv6only"))
  and (.dhcpcdConfig | contains("interface ppp-test"))
  and (.dhcpcdConfig | contains("iaid 7"))
  and (.dhcpcdConfig | contains("ia_pd 11"))
  and (.pdAfter | index("nftables.service") != null)
  and (.pdAfter | index("pppd-s88-pppoe-client-provider-handoff.service") != null)
  and (.pdRequires | index("nftables.service") != null)
  and (.pdRequires | index("pppd-s88-pppoe-client-provider-handoff.service") != null)
  and .pdBindsTo == ["pppd-s88-pppoe-client-provider-handoff.service"]
  and .pdPartOf == ["pppd-s88-pppoe-client-provider-handoff.service"]
  and (.pdExecStartPre | contains("ip link show dev ppp-test"))
  and (.pdExecStart | contains("dhcpcd -6 -d -B"))
  and .pdRestart == "always"
  and (.firewall | contains("iifname ppp-test ip6 saddr fe80::/10 udp sport 547 udp dport 546"))
  and (.firewall | contains("udp dport 547") | not)
' <<<"${result}" >/dev/null

negative="$(REPO_ROOT="${repo_root}" nix eval --impure --json --expr '
  let
    repoRoot = builtins.getEnv "REPO_ROOT";
    renderedModel.interfaces.provider-handoff.containerInterfaceName = "ens20";
    validation = import (repoRoot + "/s88/ControlModule/render/containers/module/pppoe/validation.nix") {
      inherit renderedModel;
    };
    ipv6 = {
      mode = "dhcpv6-pd";
      defaultRoute = true;
      iaid = 7;
      prefixDelegationRequestId = 11;
      duidMode = "persistent";
      resolverMode = "disabled";
      ipv4Mode = "disabled";
      routerSolicitation = false;
      fallbackPolicy = "none";
    };
    base = {
      interface = "provider-handoff";
      runtimeInterface = "ppp-test";
      credentials = {
        usernameFile = "/run/secrets/test-username";
        passwordFile = "/run/secrets/test-password";
      };
      inherit ipv6;
    };
    rejected = value: validation.clientAssertion value == false;
  in {
    missingIaid = rejected (base // { ipv6 = builtins.removeAttrs ipv6 [ "iaid" ]; });
    ipv4Enabled = rejected (base // { ipv6 = ipv6 // { ipv4Mode = "enabled"; }; });
    routerSolicitation = rejected (base // { ipv6 = ipv6 // { routerSolicitation = true; }; });
    fallbackEnabled = rejected (base // { ipv6 = ipv6 // { fallbackPolicy = "slaac"; }; });
    inventedField = rejected (base // { ipv6 = ipv6 // { inventedPppInterface = "ppp0"; }; });
    resolverEnabled = rejected (base // { ipv6 = ipv6 // { resolverMode = "enabled"; }; });
    changedIaid = rejected (base // { ipv6 = ipv6 // { iaid = 0; }; });
    pdRequestIdZero = rejected (base // { ipv6 = ipv6 // { prefixDelegationRequestId = 0; }; });
    missingPdRequestId = rejected (base // { ipv6 = builtins.removeAttrs ipv6 [ "prefixDelegationRequestId" ]; });
    differentInterface = rejected (base // { interface = "nonexistent"; });
  }
')"
jq -e 'all(.[]; . == true)' <<<"${negative}" >/dev/null

# --- Ordinal 3: Remove firewall/PPPoE ordering and require rejection ---
# Checker: verify nominal pdAfter ordering places nftables.service before any pppd service
ordering_check() {
  local candidate_json="$1"
  jq -e '
    .pdAfter as $a |
    (([$a | to_entries[] | select(.value | startswith("pppd"))] | .[0].key // -1) // -1) as $pppd_pos |
    (([$a | to_entries[] | select(.value == "nftables.service")] | .[0].key // -1) // -1) as $nft_pos |
    $nft_pos >= 0 and $pppd_pos > $nft_pos
  ' <<<"${candidate_json}" >/dev/null
}

# Nominal passes the ordering check
if ! ordering_check "${result}"; then
  echo "FAIL FS-800 ordinal 3: nominal firewall/PPPoE ordering missing" >&2
  exit 1
fi

# Mutation: swap nftables.service out of position (produce bad ordering by
# removing nftables.service from pdAfter, then the structural check fails)
mutant_pd_after="$(jq -c '.pdAfter - ["nftables.service"]' <<<"${result}")"
mutant_ordering_json="$(jq --argjson a "${mutant_pd_after}" '.pdAfter = $a' <<<"${result}")"
if ordering_check "${mutant_ordering_json}"; then
  echo "FAIL FS-800 ordinal 3: removed firewall/PPPoE ordering was not rejected" >&2
  exit 1
fi

# --- Ordinal 3 part 2: Interface wait succeed while absent ---
# Checker: verify ExecStartPre contains a fail-closed interface wait
wait_check() {
  local candidate_json="$1"
  jq -e '
    .pdExecStartPre | contains("ip link show dev ppp-test")
    and (contains("|| true") | not)
  ' <<<"${candidate_json}" >/dev/null
}

# Nominal passes the wait check
if ! wait_check "${result}"; then
  echo "FAIL FS-800 ordinal 3: nominal interface wait not fail-closed" >&2
  exit 1
fi

# Mutation: make ExecStartPre succeed even when ppp-test is absent
mutant_wait_exec="$(jq -r '.pdExecStartPre' <<<"${result}")"
mutant_wait_exec="${mutant_wait_exec//ip link show dev ppp-test/true}"
mutant_wait_json="$(jq --arg e "${mutant_wait_exec}" '.pdExecStartPre = $e' <<<"${result}")"
if wait_check "${mutant_wait_json}"; then
  echo "FAIL FS-800 ordinal 3: interface wait succeed-while-absent was not rejected" >&2
  exit 1
fi

# --- Ordinal 4: Widen the link-local UDP 547-to-546 rule and require rejection ---
# Checker: verify firewall contains the exact restricted rule and no broad
# udp-dport-547 rule that is not also restricted to iifname ppp-test + fe80::/10 + sport 547
firewall_check() {
  local candidate_text="$1"
  # Must have the correct restricted rule
  echo "${candidate_text}" | grep -q 'iifname ppp-test ip6 saddr fe80::/10 udp sport 547 udp dport 546'
  local has_restricted=$?
  # Count lines with udp dport 547 that are NOT the restricted rule
  local broad_count
  broad_count=$(echo "${candidate_text}" | grep 'udp dport 547' | grep -v 'iifname ppp-test ip6 saddr fe80::/10 udp sport 547 udp dport 546' | grep -c . || true)
  [[ $has_restricted -eq 0 && $broad_count -eq 0 ]]
}

# Nominal passes the firewall check
if ! firewall_check "$(jq -r '.firewall' <<<"${result}")"; then
  echo "FAIL FS-800 ordinal 4: nominal firewall check failed" >&2
  exit 1
fi

# Mutation: add a broad udp dport 547 rule not restricted to ppp-test/fe80::/10/sport 547
mutant_fw_text="$(jq -r '.firewall' <<<"${result}")"
mutant_fw_text="${mutant_fw_text}
nft add rule inet filter input udp dport 547 counter accept"
if firewall_check "${mutant_fw_text}"; then
  echo "FAIL FS-800 ordinal 4: widened link-local UDP 547-to-546 rule was not rejected" >&2
  exit 1
fi

echo 'PASS FS-800-HDS-030-SDS-020-SMS-020: NixOS PPPoE IPv6/PD materialization'
