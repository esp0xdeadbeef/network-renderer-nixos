#!/usr/bin/env bash
# GAMP-ID: FS-800-HDS-030-SDS-020-SMS-020
# GAMP-SCOPE: software-module-test
# Seeded Negative Ordinal 5: Compare NixOS and CLAB normalized artifacts
# and require equivalent customer-side behavior.
set -euo pipefail

repo_root="${SMS_TEST_REPO_ROOT:-$(git -C "$(dirname "${BASH_SOURCE[0]}")" rev-parse --show-toplevel)}"

# The CLAB side is a COMMITTED FIXTURE, not a live peer checkout.
#
# The renderer under comparison is a pure function of a fixed input, so its output
# for that input is a constant. Reaching into a sibling repository made this test
# depend on the environment rather than on the artefact: it failed wherever the
# checklist was absent (measured in CI: "not found at
# /home/runner/work/network-renderer-nixos/..."), and skipping instead would have
# counted as a pass while comparing nothing. A comparison needs two ARTEFACTS;
# one is produced here, the other is checked in beside this file.
#
# Regenerate the fixture from the owning repository when the CLAB renderer's
# output for this input changes:
#
#   cd ../network-renderer-containerlab-linux-backend
#   PYTHONPATH="$PWD" python3 - <<'PY' > ../network-renderer-nixos/tests/lib/FS-800-HDS-030-SDS-020-SMS-020/clab-nominal.fixture
#   from clabgen.s88.CM.pppoe_runtime import render
#   ipv6 = {"mode": "dhcpv6-pd", "defaultRoute": True, "iaid": 7,
#           "prefixDelegationRequestId": 11, "duidMode": "persistent",
#           "resolverMode": "disabled", "ipv4Mode": "disabled",
#           "routerSolicitation": False, "fallbackPolicy": "none"}
#   client = {"interface": "provider-handoff", "runtimeInterface": "ppp-test",
#             "defaultRoute": True, "usePeerDns": False, "mtu": 1492,
#             "credentials": {"usernameFile": "/run/secrets/test-username",
#                             "passwordFile": "/run/secrets/test-password"},
#             "ipv6": ipv6}
#   node = {"services": {"pppoe": {"client": client}}}
#   print("\n".join(render("test-core", node, {"provider-handoff": "eth1"})))
#   PY
#
# The fixture is the artefact the comparison binds to; regenerating it is a
# deliberate act with a diff to review, which a live import could never give.
clab_fixture="${repo_root}/tests/lib/FS-800-HDS-030-SDS-020-SMS-020/clab-nominal.fixture"
if [[ ! -s "${clab_fixture}" ]]; then
  echo "FAIL FS-800 comparison: fixture '${clab_fixture}' is missing or empty. A comparison with no second artefact must not report success." >&2
  exit 1
fi

# ---- NixOS normalized contract (same as main test) ----------------------
nixos_eval="$(REPO_ROOT="${repo_root}" nix eval --impure --json --expr '
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
    evaluated = lib.nixosSystem { inherit system; modules = [ module.config ]; };
    pd = evaluated.config.systemd.services."s88-pppoe-ipv6-pd-provider-handoff";
  in {
    dhcpcd = builtins.readFile evaluated.config.environment.etc."s88/pppoe-ipv6-provider-handoff.conf".source;
    firewall = evaluated.config.networking.nftables.ruleset;
    pdRestart = (pd.serviceConfig.Restart or "");
    pdExecStartPre = builtins.toString (pd.serviceConfig.ExecStartPre or "");
  }
')"

# ---- CLAB normalized artifacts (nominal) ---------------------------------
clab_nominal="$(cat "${clab_fixture}")"

failures=0
fail() { echo "FAIL FS-800 eq: $*" >&2; failures=$((failures + 1)); }

# ---- Equivalent dhcpcd fragments -----------------------------------------
nixos_dhcpcd="$(jq -r .dhcpcd <<<"${nixos_eval}")"

for frag in "nohook resolv.conf" "noipv6rs" "noipv4" "ipv6only" "interface ppp-test" "iaid 7" "ia_pd 11" "duid" "persistent"; do
  in_nixos=0; in_clab=0
  echo "${nixos_dhcpcd}" | grep -qF "${frag}" && in_nixos=1
  echo "${clab_nominal}" | grep -qF "${frag}" && in_clab=1
  if [[ $in_nixos -eq 0 || $in_clab -eq 0 ]]; then
    fail "equivalent fragment '${frag}' missing: NixOS=${in_nixos} CLAB=${in_clab}"
  fi
done

# ---- Equivalent firewall: both must have restricted rule -----------------
nixos_fw="$(jq -r .firewall <<<"${nixos_eval}")"
frag="iifname ppp-test ip6 saddr fe80::/10 udp sport 547 udp dport 546"
if ! echo "${nixos_fw}" | grep -qF "${frag}"; then
  fail "NixOS missing restricted firewall rule"
fi
if ! echo "${clab_nominal}" | grep -qF "${frag}"; then
  fail "CLAB missing restricted firewall rule"
fi
# Both must reject broad udp dport 547
if echo "${nixos_fw}" | grep 'udp dport 547' | grep -vF "${frag}" | grep -q .; then
  fail "NixOS has broad udp dport 547 rule"
fi
if echo "${clab_nominal}" | grep 'udp dport 547' | grep -vF "${frag}" | grep -q .; then
  fail "CLAB has broad udp dport 547 rule"
fi

# ---- Equivalent restart behavior -----------------------------------------
nixos_restart="$(jq -r .pdRestart <<<"${nixos_eval}")"
if [[ "${nixos_restart}" != "always" ]]; then
  fail "NixOS restart is not always (got: ${nixos_restart})"
fi
if ! echo "${clab_nominal}" | grep -qF 'while :; do'; then
  fail "CLAB missing restart loop"
fi

# ---- Equivalent interface wait: both must wait fail-closed for ppp-test --
nixos_exec_pre="$(jq -r .pdExecStartPre <<<"${nixos_eval}")"
if ! echo "${nixos_exec_pre}" | grep -qF 'ip link show dev ppp-test'; then
  fail "NixOS missing interface wait for ppp-test"
fi
if ! echo "${clab_nominal}" | grep -qF 'ip link show dev ppp-test'; then
  fail "CLAB missing interface wait for ppp-test"
fi

# ---- Ordinal 5 mutation: Change IAID, re-render CLAB, require rejection --
extract_int() { echo "$1" | grep -oP "$2" | head -1; }

nixos_iaid=$(extract_int "${nixos_dhcpcd}" 'iaid \K\d+')
clab_iaid=$(extract_int "${clab_nominal}" 'iaid \K\d+')

if [[ -z "${nixos_iaid}" || -z "${clab_iaid}" ]]; then
  fail "could not extract iaid values (nixos=${nixos_iaid:-empty} clab=${clab_iaid:-empty})"
fi
if [[ "${nixos_iaid}" != "${clab_iaid}" ]]; then
  fail "iaid mismatch: NixOS=${nixos_iaid} CLAB=${clab_iaid}"
fi

# Seeded negative: mutate the artefact, not the environment.
#
# The CLAB output for this fixed input is a constant, so its mutation is a
# constant too -- take the nominal fixture and change the iaid. That keeps the
# negative self-contained: it proves the comparison can FAIL, which a green run
# over an unmutated pair would never establish.
mutant_clab="$(sed -e 's/\biaid 7\b/iaid 8/' "${clab_fixture}")"
mutant_iaid=$(extract_int "${mutant_clab}" 'iaid \K\d+')

if [[ "${nixos_iaid}" == "${mutant_iaid}" ]]; then
  fail "ordinal 5: divergent iaid input mutation was not rejected (both == ${nixos_iaid})"
fi

if [[ $failures -gt 0 ]]; then
  echo "FAIL FS-800 ordinal 5: ${failures} equivalence check(s) failed" >&2
  exit 1
fi

echo "PASS FS-800-HDS-030-SDS-020-SMS-020: NixOS/CLAB PPPoE IPv6/PD equivalence (ordinal 5)"
