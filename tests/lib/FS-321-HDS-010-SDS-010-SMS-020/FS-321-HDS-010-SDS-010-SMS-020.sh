#!/usr/bin/env bash
# GAMP-ID: FS-321-HDS-010-SDS-010-SMS-020
# GAMP-SCOPE: software-module-test
#
# SPEC:   GAMP/SMS/FS-321-HDS-010-SDS-010-SMS-020.md
# OWNER:  network-renderer-nixos
# MODULE: bounded-custom-service
#
# Behavioural: renders the real single-wan fixture through the renderer's public
# entry and asserts on the rendered config. Not executed before commit.
set -euo pipefail

repo_root="${SMS_TEST_REPO_ROOT:-$(git -C "$(dirname "${BASH_SOURCE[0]}")" rev-parse --show-toplevel)}"
source "${repo_root}/tests/lib/test-common.sh"

render_json="$(mktemp)"
tmp_dir="$(mktemp -d "${TMPDIR:-/var/tmp}/network-renderer-nixos-bounded-custom-service.XXXXXX")"
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


# P1: every systemd service the render emits must be attributable. The SMS allows a
# custom service only for a declared gap, and requires a failure behavior and a
# startup ordering on it. A service with no description and no ordering is
# unbounded.
services="$(_jq -r "(.systemd.services? // {}) | keys[]" "${render_json}" 2>/dev/null || true)"
if [[ -n "${services}" ]]; then
  unbounded="$(_jq -r "
    [(.systemd.services // {}) | to_entries[]
     | select(((.value.description? // \"\") | length) == 0
              and ((.value.after? // []) | length) == 0
              and ((.value.wantedBy? // []) | length) == 0)
     | .key] | join(\",\")" "${render_json}" 2>/dev/null || true)"
  [[ -z "${unbounded}" ]] || fail "P1 these custom services carry no description, ordering or activation, so they are unbounded: ${unbounded}"
fi

# P1: no custom service may own a semantic the platform expresses. Routing, DNS and
# firewall behavior belong to systemd.network, the DNS module and nftables.
offenders="$(_jq -r "
  [(.systemd.services // {}) | to_entries[]
   | select((((.value.script? // \"\") + ((.value.serviceConfig.ExecStart? // \"\") | tostring)) | test(\"\\\\b(ip route|nft|unbound|resolved)\\\\b\")))
   | .key] | join(\",\")" "${render_json}" 2>/dev/null || true)"
[[ -z "${offenders}" ]] || fail "P1 these services own platform-expressible semantics: ${offenders}"

# SN1: the detector must flag a synthetic unbounded service, so it can fail.
synth="${tmp_dir}/synth.json"
printf "%s" "{\"systemd\":{\"services\":{\"gap-filler\":{}}}}" >"${synth}"
found="$(_jq -r "[(.systemd.services // {}) | to_entries[] | select(((.value.description? // \"\") | length) == 0 and ((.value.after? // []) | length) == 0 and ((.value.wantedBy? // []) | length) == 0) | .key] | length" "${synth}" 2>/dev/null || echo 0)"
[[ "${found}" != "0" ]] || fail "SN1 the unbounded-service detector did not flag a service with no description, ordering or activation"


echo "PASS bounded-custom-service"
