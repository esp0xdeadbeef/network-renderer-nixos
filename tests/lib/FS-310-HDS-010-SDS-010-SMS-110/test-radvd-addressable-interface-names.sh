#!/usr/bin/env bash
# GAMP-ID: FS-310-HDS-010-SDS-010-SMS-110
# GAMP-SCOPE: software-module-test
#
# Every interface name this renderer emits must be one the RA daemon can
# address.
#
# radvd 2.21 reserves words that the site model uses as tenant link names
# (`clients`, `iot`, `dmz`, `mgmt`, `svc`, `unlock`, ...). Its scanner matches a
# keyword before the generic STRING rule and `interface` takes
# `T_INTERFACE name` where `name : STRING`, so such a name cannot be expressed:
#
#     interface clients { ... };   ->  radvd-clients.conf:1 error: syntax error
#
# Neither workaround works, and both were measured against radvd 2.21:
#
#   * quoting parses, but the scanner copies the token verbatim *including the
#     quote characters*, so radvd then reports `Device "clients" does not
#     exist.` -- the quotes become part of the name;
#   * a kernel altname resolves through if_nametoindex but radvd's setup_iface
#     reads /proc/sys/net/ipv6/conf/<name>/, which exists only for the real
#     link name, so it logs `... is not ready and setup_iface failed` and never
#     advertises.
#
# So the name has to be chosen such that no radvd keyword is ever handed to
# radvd. This renderer already owns container interface names (it renames host
# veths to `containerInterfaceName`), so `validInterfaceName` -- the predicate
# every naming path runs through -- rejects the reserved words.
#
# The case asserts the predicate and the derivation, and then runs the real
# radvd binary over a config naming every derived interface, so the claim is
# about radvd's grammar rather than about a list someone guessed.
set -euo pipefail

repo_root="${SMS_TEST_REPO_ROOT:-$(git -C "$(dirname "${BASH_SOURCE[0]}")" rev-parse --show-toplevel)}"
source "${repo_root}/tests/lib/test-common.sh"

# The radvd keywords a site model could plausibly use as a tenant link name.
# `clients` is the one that broke cobalt.
reserved=(clients prefix route dnssl abro interface)

named="$(IFS=,; echo "${reserved[*]}")"

case_dir="$(mktemp -d)"
trap 'rm -rf "${case_dir}"' EXIT

result_file="${case_dir}/naming.json"
nix eval --impure --json --expr '
  let
    repoRoot = "'"${repo_root}"'";
    flake = builtins.getFlake ("path:" + repoRoot);
    lib = flake.inputs.nixpkgs.lib;
    naming = import (repoRoot + "/s88/ControlModule/mapping/container-runtime/interfaces/naming.nix") {
      inherit lib;
    };
    reserved = lib.splitString "," "'"${named}"'";
    derived = builtins.listToAttrs (
      map (name: {
        inherit name;
        value = {
          valid = naming.validInterfaceName name;
          derivedName = naming.semanticBaseInterfaceName name;
          derivedValid = naming.validInterfaceName (naming.semanticBaseInterfaceName name);
        };
      }) reserved
    );
  in
  derived
' > "${result_file}"

failures=()

# 1. The reserved word itself must be rejected, or a caller that skipped the
#    derivation would hand it straight to radvd.
while IFS=$'\t' read -r name valid derived_name derived_valid; do
  [[ -n "${name}" ]] || continue
  if [[ "${valid}" == "true" ]]; then
    failures+=("${name}: validInterfaceName accepted a radvd keyword")
  fi
  # 2. The derivation must produce a name the predicate accepts.
  if [[ "${derived_valid}" != "true" ]]; then
    failures+=("${name}: semanticBaseInterfaceName produced '${derived_name}', which is still not addressable")
    continue
  fi
  # 3. And it must not be the keyword it came from (a no-op derivation would
  #    pass the predicate check only if the predicate were wrong).
  if [[ "${derived_name}" == "${name}" ]]; then
    failures+=("${name}: semanticBaseInterfaceName left the reserved name unchanged")
  fi
done < <(python3 - "${result_file}" <<'PY'
import json, sys
for name, entry in sorted(json.load(open(sys.argv[1])).items()):
    print(
        "\t".join(
            [
                name,
                "true" if entry["valid"] else "false",
                entry["derivedName"],
                "true" if entry["derivedValid"] else "false",
            ]
        )
    )
PY
)

# 4. radvd's own grammar over every derived name: the real binary, check mode.
radvd_bin="$(nix build --no-link --print-out-paths --impure --expr '
  (builtins.getFlake "path:'"${repo_root}"'").inputs.nixpkgs.legacyPackages.${builtins.currentSystem}.radvd
' | tail -1)/bin/radvd"

while IFS=$'\t' read -r name _derived_name _ignored _ignored2; do
  [[ -n "${name}" ]] || continue
  cfg="${case_dir}/radvd-${name}.conf"
  cat > "${cfg}" <<EOF
interface ${_derived_name} {
  AdvSendAdvert on;
  MinRtrAdvInterval 10;
  MaxRtrAdvInterval 30;
  prefix fd42:1::/64 {
    AdvOnLink on;
    AdvAutonomous on;
  };
};
EOF
  if ! "${radvd_bin}" -C "${cfg}" -c > "${case_dir}/out" 2>&1 || grep -q "syntax error" "${case_dir}/out"; then
    failures+=("${name} -> ${_derived_name}: radvd rejected the config: $(tr '\n' ' ' < "${case_dir}/out")")
  fi
done < <(python3 - "${result_file}" <<'PY'
import json, sys
for name, entry in sorted(json.load(open(sys.argv[1])).items()):
    print("\t".join([name, entry["derivedName"], "", ""]))
PY
)

if (( ${#failures[@]} > 0 )); then
  printf 'FAIL radvd-addressable-interface-names:\n' >&2
  printf '  %s\n' "${failures[@]}" >&2
  exit 1
fi

pass "radvd-addressable-interface-names (${reserved[*]})"
