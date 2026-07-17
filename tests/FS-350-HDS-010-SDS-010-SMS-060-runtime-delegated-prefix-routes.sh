#!/usr/bin/env bash
# GAMP-ID: FS-350-HDS-010-SDS-010-SMS-060
# GAMP-SCOPE: software-module-test
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${repo_root}/tests/lib/test-common.sh"

result="$({ REPO_ROOT="${repo_root}" nix eval --impure --json --expr '
  let
    root = builtins.getEnv "REPO_ROOT";
    flake = builtins.getFlake root;
    lib = flake.inputs.nixpkgs.lib;
    build = route:
      import (root + "/s88/ControlModule/render/container-networks/interface-units/dynamic-delegated-routes.nix") {
        inherit lib;
        interfaces = {
          tenant = {
            sourceKind = "p2p";
            routes = [ route ];
          };
        };
        interfaceNames = [ "tenant" ];
        renderedInterfaceNames = { tenant = "ens3"; };
        policyRoutingByInterface = {
          routes = { tenant = [ ]; };
          rules = { tenant = [ ]; };
          dynamicSourceRules = [ ];
        };
        delegatedPrefixSourceForRoute = candidate: candidate.sourceFile or null;
        isExternalValidationDelegatedPrefixRoute = _route: false;
      };
    route = {
      family = 6;
      sourceFile = "/run/secrets/subnet-ipv6-vlan2";
      tenant = "vlan2";
      prefixName = "vlan2-public";
      prefixPostfix = "4444";
      delegatedPrefixLength = 48;
      perTenantPrefixLength = 64;
      slot = 2;
      via6 = "fd00::1";
      intent = {
        kind = "runtime-routed-prefix-return";
        source = "intent-routed-prefix";
      };
    };
    rendered = builtins.head (build route);
    missing = builtins.tryEval (builtins.deepSeq (build (builtins.removeAttrs route [ "slot" ])) true);
  in {
    metadata =
      rendered.deriveTenantPrefix == true
      && rendered.delegatedPrefixLength == 48
      && rendered.perTenantPrefixLength == 64
      && rendered.slot == 2
      && rendered.tenant == "vlan2"
      && rendered.prefixName == "vlan2-public"
      && rendered.prefixPostfix == "4444";
    missingRejected = missing.success == false;
  }
'; } )"

jq -e '.metadata == true and .missingRejected == true' <<<"${result}" >/dev/null || {
  printf 'FAIL FS-350-HDS-010-SDS-010-SMS-060: renderer candidate lost or defaulted prefix derivation metadata\n' >&2
  exit 1
}

helper="${repo_root}/s88/ControlModule/render/containers/module/runtime-delegated-prefix.py"
test -f "${helper}" || {
  printf 'FAIL FS-350-HDS-010-SDS-010-SMS-060: runtime tenant-prefix derivation helper missing\n' >&2
  exit 1
}

tmp_dir="$(mktemp -d)"
trap 'rm -rf "${tmp_dir}"' EXIT
source_file="${tmp_dir}/delegated-prefix"
printf '%s\n' '2001:db8:350::/48' >"${source_file}"

derived="$(${helper} \
  --source "${source_file}" \
  --family 6 \
  --delegated-prefix-length 48 \
  --tenant-prefix-length 64 \
  --slot 2)"
test "${derived}" = '2001:db8:350:2::/64' || {
  printf 'FAIL FS-350-HDS-010-SDS-010-SMS-060: wrong derived tenant prefix\n' >&2
  exit 1
}

stderr_file="${tmp_dir}/stderr"
printf '%s\n' '2001:db8:350::/56' >"${source_file}"
if "${helper}" \
  --source "${source_file}" \
  --family 6 \
  --delegated-prefix-length 48 \
  --tenant-prefix-length 64 \
  --slot 2 >"${tmp_dir}/stdout" 2>"${stderr_file}"; then
  printf 'FAIL FS-350-HDS-010-SDS-010-SMS-060: wrong parent length accepted\n' >&2
  exit 1
fi
grep -q '^diagnostic.runtime-delegated-prefix-invalid:' "${stderr_file}" || {
  printf 'FAIL FS-350-HDS-010-SDS-010-SMS-060: redacted failure class missing\n' >&2
  exit 1
}
if grep -q '2001:db8' "${stderr_file}" || test -s "${tmp_dir}/stdout"; then
  printf 'FAIL FS-350-HDS-010-SDS-010-SMS-060: protected prefix leaked on failure\n' >&2
  exit 1
fi

printf 'PASS FS-350-HDS-010-SDS-010-SMS-060 runtime delegated tenant-prefix routes\n'
