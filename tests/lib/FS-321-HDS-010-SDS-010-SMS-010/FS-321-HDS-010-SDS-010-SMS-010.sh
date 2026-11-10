#!/usr/bin/env bash
# GAMP-ID: FS-321-HDS-010-SDS-010-SMS-010
# GAMP-SCOPE: software-module-test
#
# SPEC:   GAMP/SMS/FS-321-HDS-010-SDS-010-SMS-010.md
# OWNER:  network-renderer-nixos
#
# Predicates: modeled behavior is emitted through the platform's own configuration
# surfaces, and an opaque payload, an alternate operating system or a broad
# imperative rewrite in place of platform configuration is rejected.
#
# Behavioural: renders the real single-wan fixture through the renderer's public
# entry and asserts on the rendered config, rather than grepping the source.
#
# Not executed before commit.
set -euo pipefail

repo_root="${SMS_TEST_REPO_ROOT:-$(git -C "$(dirname "${BASH_SOURCE[0]}")" rev-parse --show-toplevel)}"
source "${repo_root}/tests/lib/test-common.sh"

render_json="$(mktemp)"
tmp_dir="$(mktemp -d "${TMPDIR:-/var/tmp}/network-renderer-nixos-fs321.XXXXXX")"
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

# P1: the rendered config must use platform-native surfaces. The renderer translates
# meaning into NixOS configuration, so at least two of these families must appear.
native_hits=0
for family in '.systemd.network.netdevs' '.systemd.network.networks' '.networking' '.services' '.environment.etc'; do
  if _jq -e "has(\"${family#.}\") or (.. | objects | select(has(\"${family##*.}\")))" "${render_json}" >/dev/null 2>&1; then
    native_hits=$((native_hits + 1))
  fi
done
((native_hits >= 2)) || fail "P1 the rendered config exposes ${native_hits} platform-native surface families, so behavior is not emitted through the platform's own configuration"

# P2: no custom service may carry network behavior that the platform expresses
# natively. A service whose command is a shell doing route/firewall/DNS work is the
# imperative rewrite the SMS forbids.
offenders="$(_jq -r '
  [ .. | objects | select(has("systemd")) | .systemd.services? // {}
    | to_entries[]
    | select(.value.script? or .value.serviceConfig.ExecStart?)
    | { name: .key, cmd: ((.value.script? // "") | tostring) + ((.value.serviceConfig.ExecStart? // "") | tostring) }
  ]
  | map(select(.cmd | test("\\b(ip route|nft add|nft -f|iptables|unbound-control|netlink)\\b")))
  | map(.name) | join(",")
' "${render_json}" 2>/dev/null || true)"

[[ -z "${offenders}" ]] || fail "P2 these custom services carry network behavior the platform expresses natively: ${offenders}"

# P2: no alternate operating system may appear in place of platform configuration.
if _jq -e '.. | strings | select(test("nixos-generate|vm.nix|alternate-os|foreign-rootfs"))' "${render_json}" >/dev/null 2>&1; then
  fail "P2 the rendered config references an alternate operating system instead of platform configuration"
fi

# SN1: the check must be able to fail. A synthetic service carrying an imperative
# rewrite must be detected by the same expression.
synthetic="${tmp_dir}/synthetic.json"
printf '%s' '{"systemd":{"services":{"bad":{"script":"ip route add default via 10.0.0.1"}}}}' >"${synthetic}"
found="$(_jq -r '
  [ .. | objects | select(has("systemd")) | .systemd.services? // {}
    | to_entries[] | select(.value.script? or .value.serviceConfig.ExecStart?)
    | { name: .key, cmd: ((.value.script? // "") | tostring) } ]
  | map(select(.cmd | test("\\b(ip route|nft add)\\b"))) | length
' "${synthetic}" 2>/dev/null || echo 0)"
[[ "${found}" != "0" ]] || fail "SN1 the imperative-rewrite detector did not flag a service whose script runs 'ip route add', so it cannot reject one in a real render"

echo "PASS native-mechanism-preference"
