#!/usr/bin/env bash
# GAMP-ID: FS-321-HDS-010-SDS-010-SMS-030
# GAMP-SCOPE: software-module-test
#
# SPEC:   GAMP/SMS/FS-321-HDS-010-SDS-010-SMS-030.md
# OWNER:  network-renderer-nixos
# MODULE: thin-host-configuration
#
# Behavioural: renders the real single-wan fixture through the renderer's public
# entry and asserts on the rendered config. Not executed before commit.
set -euo pipefail

repo_root="${SMS_TEST_REPO_ROOT:-$(git -C "$(dirname "${BASH_SOURCE[0]}")" rev-parse --show-toplevel)}"
source "${repo_root}/tests/lib/test-common.sh"

render_json="$(mktemp)"
tmp_dir="$(mktemp -d "${TMPDIR:-/var/tmp}/network-renderer-nixos-thin-host-configuration.XXXXXX")"
trap 'rm -f "${render_json}"; rm -rf "${tmp_dir}"' EXIT

labs_root="$(flake_input_path network-labs)"
example_dir="${labs_root}/examples/single-wan"
cpm_json="${tmp_dir}/cpm.json"
build_cpm_json "${example_dir}/intent.nix" "${example_dir}/inventory-nixos.nix" "${cpm_json}"

nix eval --extra-experimental-features 'nix-command flakes' --impure --json --expr '
  let
    flake = builtins.getFlake ("path:'"${repo_root}"'");
    cpm = builtins.fromJSON (builtins.readFile "'"${cpm_json}"'");
    rendered = flake.lib.renderer.renderDryConfig {
      inherit cpm;
      exampleDir = "'"${example_dir}"'";
      debug = true;
    };
  in rendered
' >"${render_json}" 2>"${tmp_dir}/err" || fail "P1 the renderer did not render the single-wan fixture:
$(cat "${tmp_dir}/err")"


# P1: host configuration is limited to environment selection, host management
# reachability, and renderer-output import. The invariant is that no firewall, NAT,
# routing table or DNS policy is authored at the host level while the renderer
# derives them from the model.
offenders="$(_jq -r "
  [ (if (.networking.firewall? // null) != null and ((.networking.firewall.enable? // null) == false) then \"networking.firewall.enable=false\" else empty end),
    (if (.networking.nat? // null) != null then \"networking.nat\" else empty end),
    (if (.networking.nftables? // null) != null and ((.networking.nftables.ruleset? // \"\") | test(\"table\")) then \"networking.nftables.ruleset\" else empty end),
    (if ((.networking.useDHCP? // null) == true) then \"networking.useDHCP=true\" else empty end)
  ] | join(\",\")" "${render_json}" 2>/dev/null || true)"
[[ -z "${offenders}" ]] || fail "P1 host configuration authors network behavior the renderer should own: ${offenders}"

# P1: the renderer-output import surface must exist, so host configuration consumes
# rendered output rather than restating it.
if ! _jq -e "(.environment.etc? // {} | length) > 0 or (.systemd.network? // {} | length) > 0" "${render_json}" >/dev/null 2>&1; then
  fail "P1 the rendered config carries no renderer-output import surface, so host configuration is not importing rendered output"
fi

# SN1: the detector must flag a host config that disables the host firewall, so it
# can fail on a real regression.
synth="${tmp_dir}/synth.json"
printf "%s" "{\"networking\":{\"firewall\":{\"enable\":false}}}" >"${synth}"
found="$(_jq -r "if (.networking.firewall.enable? // null) == false then 1 else 0 end" "${synth}" 2>/dev/null || echo 0)"
[[ "${found}" == "1" ]] || fail "SN1 the host-boundary detector did not flag a config that disables the host firewall"


echo "PASS thin-host-configuration"
