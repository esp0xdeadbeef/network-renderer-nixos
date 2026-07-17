#!/usr/bin/env bash
# GAMP-ID: FS-970-HDS-010-SDS-020-SMS-040
# GAMP-SCOPE: software-module-test
#
# Runtime Secret DHCPv4 Reservation Materialization — NixOS renderer construction
# evidence. Proves the renderer:
#   - accepts one advertisement-level protected reservation source from CPM
#   - emits a read-only /run/secrets/... reservation source bind mount into the
#     container that runs Kea
#   - materializes the complete Kea reservation set at runtime (not at Nix
#     eval), without public per-client descriptors
#   - keeps the protected MAC and private hostname absent from the generated
#     non-secret Kea config JSON and the Nix store gen script
#   - emits the SMS-mandated diagnostics on the failure paths
#
# Seeded negatives (renderer-owned share of the SMS negative set):
#   NC3 - unapproved runtime source path  -> diagnostic.runtime-reservation-source-path-invalid
#   NC4 - missing/ambiguous secret record -> diagnostic.runtime-reservation-secret-record-invalid
#   NC5 - protected value leak            -> generated non-secret artifact must not
#                                            contain the protected MAC or private hostname
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${repo_root}/tests/lib/test-common.sh"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

protected_mac="02:10:20:aa:bb:cc"
protected_hostname="printer-serial-private"
source_file="/run/secrets/s-router-prod-vlan2-reservations.json"

# ---------------------------------------------------------------------------
# Positive case: renderer accepts a scope-level protected source, emits a
# read-only bind mount for the runtime secret, and materializes the reservation
# at runtime. The generated (non-secret) Kea config must not carry the
# protected MAC or private hostname.
# ---------------------------------------------------------------------------
scope_expr() {
  cat <<'EOF'
scope = {
  fileStem = "client-v4";
  interfaceName = "tenant-client";
  subnetId = 1;
  subnet = "10.20.20.0/24";
  pool = "10.20.20.100 - 10.20.20.199";
  router = "10.20.20.1";
  dnsServers = [ "10.20.20.1" ];
  domain = "lan.";
  scopeId = "client";
  reservations = [ ];
  reservationSource = {
    schema = "gamp-protected-reservation-set-v1";
    sourceClass = "protected";
    sourceFile = "/run/secrets/s-router-prod-vlan2-reservations.json";
  };
  leaseState = {
    service = "dhcp4";
    id = "client-v4";
    kind = "lease-state";
    mode = "ephemeral";
    required = false;
    interface = "tenant-client";
    tenant = "client";
    source = "inventory-realization";
    runtimeLocation = "ephemeral";
  };
};
EOF
}

kea_gen_script="$(
  env REPO_ROOT="${repo_root}" nix eval --raw \
    --extra-experimental-features 'nix-command flakes' \
    --impure --expr "
      let
        repoRoot = builtins.getEnv \"REPO_ROOT\";
        flake = builtins.getFlake (\"path:\" + repoRoot);
        lib = flake.inputs.nixpkgs.lib;
        pkgs = import flake.inputs.nixpkgs { system = builtins.currentSystem; };
        kea =
          import (repoRoot + \"/s88/ControlModule/access/render/kea.nix\") {
            inherit lib pkgs;
            $(scope_expr)
          };
      in
        builtins.toString kea.systemd.services.\"gen-kea-client-v4\".serviceConfig.ExecStart
    "
)"

# The unit calls the standalone materializer directly. Nix carries only public
# arguments and store paths; secret parsing is not embedded in Nix or Bash.
grep -F "$source_file" <<<"$kea_gen_script" >/dev/null \
  || fail "FAIL runtime-secret-reservation-materialization: gen script does not reference the runtime secret source file"
grep -F 'runtime-reservation-materializer.py' <<<"$kea_gen_script" >/dev/null \
  || fail "FAIL runtime-secret-reservation-materialization: systemd unit does not call the standalone materializer"
grep -F -- '--pool' <<<"$kea_gen_script" >/dev/null \
  || fail "FAIL runtime-secret-reservation-materialization: materializer command omits the modeled allocation pool"
if grep -E '/bash|/jq|runtime_descriptors|while IFS=' <<<"$kea_gen_script" >/dev/null; then
  fail "FAIL runtime-secret-reservation-materialization: secret materialization leaked back into generated Bash/jq wiring"
fi

# Protected value leak (NC5): neither the generated non-secret gen script nor
# the static config embedded in it may contain the protected MAC or the private
# hostname; those come only from the runtime secret at runtime.
if grep -F "$protected_mac" <<<"$kea_gen_script" >/dev/null; then
  fail "FAIL runtime-secret-reservation-materialization: NC5 protected MAC leaked into generated non-secret gen script"
fi
if grep -F "$protected_hostname" <<<"$kea_gen_script" >/dev/null; then
  fail "FAIL runtime-secret-reservation-materialization: NC5 protected hostname leaked into generated non-secret gen script"
fi

pass "runtime-secret-reservation-materialization positive + NC5 (gen script)"

# Execute the standalone runtime boundary with synthetic protected input. The
# output is intentionally runtime-local and may contain protected values; its
# mode must be 0600 and diagnostics must remain redacted.
materializer="${repo_root}/s88/ControlModule/access/render/runtime-reservation-materializer.py"
template_v4="${tmp}/kea-v4-template.json"
secret_v4="${tmp}/protected-v4.json"
output_v4="${tmp}/runtime/kea-v4.json"
lease_v4="${tmp}/leases-v4"

cat >"${template_v4}" <<'JSON'
{"Dhcp4":{"interfaces-config":{"interfaces":["tenant-client"]},"lease-database":{"name":"/var/lib/kea/test","persist":true,"type":"memfile"},"subnet4":[{"id":1,"subnet":"10.20.20.0/24","pools":[{"pool":"10.20.20.100 - 10.20.20.199"}],"reservations":[]}]}}
JSON
cat >"${secret_v4}" <<JSON
[
  {
    "id": "opaque-client-01",
    "scope": "client",
    "ipv4": {
      "address": "10.20.20.10",
      "mac-address": "${protected_mac}"
    },
    "hostname": "${protected_hostname}"
  }
]
JSON

python3 "${materializer}" \
  --family ipv4 \
  --scope client \
  --subnet 10.20.20.0/24 \
  --pool '10.20.20.100 - 10.20.20.199' \
  --source "${secret_v4}" \
  --template "${template_v4}" \
  --output "${output_v4}" \
  --lease-directory "${lease_v4}"

jq -e \
  --arg mac "${protected_mac}" \
  --arg address "10.20.20.10" \
  --arg hostname "${protected_hostname}" \
  '.Dhcp4.subnet4[0].reservations == [{"hw-address": $mac, "ip-address": $address, hostname: $hostname}]' \
  "${output_v4}" >/dev/null \
  || fail "FAIL runtime-secret-reservation-materialization: standalone IPv4 materializer emitted the wrong Kea record"
jq -e '.Dhcp4.subnet4[0]["reservations-out-of-pool"] == true' "${output_v4}" >/dev/null \
  || fail "FAIL runtime-secret-reservation-materialization: IPv4 runtime config did not enable out-of-pool reservations"
[[ "$(stat -c '%a' "${output_v4}")" == "600" ]] \
  || fail "FAIL runtime-secret-reservation-materialization: runtime Kea config is not mode 0600"

pass "runtime-secret-reservation-materialization standalone IPv4 positive"

assert_redacted_rejection() {
  local label="$1"
  local source="$2"
  local stderr_file="${tmp}/${label}.err"
  local rejected_output="${tmp}/${label}.json"

  if python3 "${materializer}" \
    --family ipv4 \
    --scope client \
    --subnet 10.20.20.0/24 \
    --pool '10.20.20.100 - 10.20.20.199' \
    --source "${source}" \
    --template "${template_v4}" \
    --output "${rejected_output}" \
    --lease-directory "${lease_v4}" \
    >"${tmp}/${label}.out" 2>"${stderr_file}"; then
    fail "FAIL runtime-secret-reservation-materialization: ${label} was accepted"
  fi
  grep -F 'diagnostic.runtime-reservation-secret-record-invalid' "${stderr_file}" >/dev/null \
    || fail "FAIL runtime-secret-reservation-materialization: ${label} lacked the runtime diagnostic"
  if grep -F -e "${protected_mac}" -e "${protected_hostname}" -e 'opaque-client-01' -e '10.20.20.10' "${stderr_file}" >/dev/null; then
    fail "FAIL runtime-secret-reservation-materialization: ${label} diagnostic disclosed protected data"
  fi
}

assert_redacted_rejection missing-source "${tmp}/does-not-exist.json"

invalid_json="${tmp}/invalid-json.json"
printf '%s\n' '{invalid-json' >"${invalid_json}"
assert_redacted_rejection invalid-json "${invalid_json}"

wrong_scope="${tmp}/wrong-scope.json"
jq '.[0].scope = "another-scope"' "${secret_v4}" >"${wrong_scope}"
assert_redacted_rejection wrong-scope "${wrong_scope}"

out_of_prefix="${tmp}/out-of-prefix.json"
jq '.[0].ipv4.address = "10.20.21.10"' "${secret_v4}" >"${out_of_prefix}"
assert_redacted_rejection out-of-prefix "${out_of_prefix}"

inside_dynamic_pool="${tmp}/inside-dynamic-pool.json"
jq '.[0].ipv4.address = "10.20.20.110"' "${secret_v4}" >"${inside_dynamic_pool}"
assert_redacted_rejection inside-dynamic-pool "${inside_dynamic_pool}"

invalid_mac="${tmp}/invalid-mac.json"
jq '.[0].ipv4["mac-address"] = "not-a-mac"' "${secret_v4}" >"${invalid_mac}"
assert_redacted_rejection invalid-mac "${invalid_mac}"

duplicate_identity="${tmp}/duplicate-identity.json"
jq '.[0] as $first | . + [$first | .id = "opaque-client-02" | .ipv4.address = "10.20.20.11"]' \
  "${secret_v4}" >"${duplicate_identity}"
assert_redacted_rejection duplicate-identity "${duplicate_identity}"

pass "runtime-secret-reservation-materialization IPv4 seeded negatives redacted"

template_v6="${tmp}/kea-v6-template.json"
secret_v6="${tmp}/protected-v6.json"
output_v6="${tmp}/runtime/kea-v6.json"
cat >"${template_v6}" <<'JSON'
{"Dhcp6":{"interfaces-config":{"interfaces":["tenant-client"]},"lease-database":{"name":"/var/lib/kea/test6","persist":true,"type":"memfile"},"subnet6":[{"id":1,"subnet":"2001:db8:970:2::/64","pools":[{"pool":"2001:db8:970:2::100 - 2001:db8:970:2::1ff"}],"reservations":[]}]}}
JSON
cat >"${secret_v6}" <<'JSON'
[
  {
    "id": "opaque-client-v6-01",
    "scope": "client-v6",
    "ipv6": {
      "address": "2001:db8:970:2::40",
      "iid": "0000:0000:0000:0040",
      "iid-stability": "stable",
      "duid": "000400000000000000000000000000000040",
      "iaid": 1
    }
  }
]
JSON

python3 "${materializer}" \
  --family ipv6 \
  --scope client-v6 \
  --subnet 2001:db8:970:2::/64 \
  --pool '2001:db8:970:2::100 - 2001:db8:970:2::1ff' \
  --source "${secret_v6}" \
  --template "${template_v6}" \
  --output "${output_v6}" \
  --lease-directory "${tmp}/leases-v6"

jq -e \
  '.Dhcp6.subnet6[0].reservations == [{duid: "000400000000000000000000000000000040", "ip-addresses": ["2001:db8:970:2::40"]}]' \
  "${output_v6}" >/dev/null \
  || fail "FAIL runtime-secret-reservation-materialization: standalone IPv6 materializer did not preserve DUID/address identity"
jq -e '.Dhcp6.subnet6[0]["reservations-out-of-pool"] == true' "${output_v6}" >/dev/null \
  || fail "FAIL runtime-secret-reservation-materialization: IPv6 runtime config did not enable out-of-pool reservations"

iid_mismatch="${tmp}/iid-mismatch.json"
jq '.[0].ipv6.iid = "0000:0000:0000:0041"' "${secret_v6}" >"${iid_mismatch}"
if python3 "${materializer}" \
  --family ipv6 --scope client-v6 --subnet 2001:db8:970:2::/64 \
  --pool '2001:db8:970:2::100 - 2001:db8:970:2::1ff' \
  --source "${iid_mismatch}" --template "${template_v6}" \
  --output "${tmp}/iid-mismatch-output.json" --lease-directory "${tmp}/leases-v6" \
  >"${tmp}/iid-mismatch.out" 2>"${tmp}/iid-mismatch.err"; then
  fail "FAIL runtime-secret-reservation-materialization: IPv6 IID/address mismatch was accepted"
fi
grep -F 'diagnostic.runtime-reservation-secret-record-invalid' "${tmp}/iid-mismatch.err" >/dev/null \
  || fail "FAIL runtime-secret-reservation-materialization: IPv6 IID mismatch lacked redacted diagnostic"

pass "runtime-secret-reservation-materialization standalone IPv6 + IID negative"

# ---------------------------------------------------------------------------
# Bind-mount emission: the container that runs Kea must bind-mount the runtime
# secret source file read-only.
# ---------------------------------------------------------------------------
nix_eval_true_or_fail \
  runtime-secret-reservation-bind-mount \
  env REPO_ROOT="${repo_root}" \
    nix eval \
    --extra-experimental-features 'nix-command flakes' \
    --impure --expr '
      let
        repoRoot = builtins.getEnv "REPO_ROOT";
        flake = builtins.getFlake ("path:" + repoRoot);
        lib = flake.inputs.nixpkgs.lib;
        renderedModel = {
          unitName = "access-vlan2";
          roleName = "access";
          hostBridge = "lan2";
          interfaces.tenant-client = {
            interfaceName = "tenant-client";
            sourceKind = "tenant";
            addresses = [ "10.20.20.1/24" ];
          };
          runtimeTarget.advertisements.dhcp4 = [
            {
              id = "client-v4";
              enabled = true;
              interface = "tenant-client";
              tenant = "client";
              subnet = "10.20.20.0/24";
              pool = "10.20.20.100 - 10.20.20.199";
              router = "10.20.20.1";
              reservations = [ ];
              reservationSource = {
                schema = "gamp-protected-reservation-set-v1";
                sourceClass = "protected";
                sourceFile = "/run/secrets/s-router-prod-vlan2-reservations.json";
              };
            }
          ];
        };
        emission = import (repoRoot + "/s88/ControlModule/render/containers/emission.nix") {
          inherit lib renderedModel;
          debugEnabled = false;
          deploymentHostName = "s-router-nixos";
          containerName = "access-vlan2";
          firewallArg = { enable = false; };
          alarmModel = { };
          uplinks = { };
          wanUplinkName = null;
        };
        mount = emission.bindMounts."/run/secrets/s-router-prod-vlan2-reservations.json" or null;
      in
        mount != null
        && mount.hostPath == "/run/secrets/s-router-prod-vlan2-reservations.json"
        && mount.isReadOnly == true
    '

pass "runtime-secret-reservation-materialization bind mount (read-only)"

# ---------------------------------------------------------------------------
# NC3 - unapproved runtime source path: an advertisement-level reservationSource
# sourceFile outside /run/secrets/ shall be rejected by the renderer
# advertisement authoritative boundary with
# diagnostic.runtime-reservation-source-path-invalid.
# ---------------------------------------------------------------------------
nc3_err="${tmp}/nc3.err"
if env REPO_ROOT="${repo_root}" nix eval \
  --extra-experimental-features 'nix-command flakes' \
  --impure --expr '
    let
      repoRoot = builtins.getEnv "REPO_ROOT";
      flake = builtins.getFlake ("path:" + repoRoot);
      lib = flake.inputs.nixpkgs.lib;
      model =
        import (repoRoot + "/s88/ControlModule/access/lookup/advertisements.nix") {
          inherit lib;
          containerModel = {
            interfaces.tenant-client = {
              interfaceName = "tenant-client";
              sourceKind = "tenant";
              addresses = [ "10.20.20.1/24" ];
            };
            runtimeTarget.advertisements.dhcp4 = [
              {
                id = "client-v4";
                enabled = true;
                interface = "tenant-client";
                tenant = "client";
                subnet = "10.20.20.0/24";
                pool = "10.20.20.100 - 10.20.20.199";
                router = "10.20.20.1";
                reservations = [ ];
                reservationSource = {
                  schema = "gamp-protected-reservation-set-v1";
                  sourceClass = "protected";
                  sourceFile = "/etc/kea/unapproved-reservations.json";
                };
              }
            ];
          };
        };
    in
      builtins.deepSeq model true
  ' >"${tmp}/nc3.out" 2>"${nc3_err}"; then
  fail "FAIL runtime-secret-reservation-materialization: NC3 unapproved source path was accepted"
fi
grep -F "diagnostic.runtime-reservation-source-path-invalid" "${nc3_err}" >/dev/null || {
  cat "${nc3_err}" >&2
  fail "FAIL runtime-secret-reservation-materialization: NC3 did not emit diagnostic.runtime-reservation-source-path-invalid"
}

pass "runtime-secret-reservation-materialization NC3 (unapproved source path)"

# A protected runtime source attached to one public reservation descriptor is
# the superseded privacy contract and must fail closed.
per_record_err="${tmp}/per-record.err"
if env REPO_ROOT="${repo_root}" nix eval \
  --extra-experimental-features 'nix-command flakes' \
  --impure --expr '
    let
      repoRoot = builtins.getEnv "REPO_ROOT";
      flake = builtins.getFlake ("path:" + repoRoot);
      lib = flake.inputs.nixpkgs.lib;
      model =
        import (repoRoot + "/s88/ControlModule/access/lookup/advertisements.nix") {
          inherit lib;
          containerModel = {
            interfaces.tenant-client = {
              interfaceName = "tenant-client";
              sourceKind = "tenant";
              addresses = [ "10.20.20.1/24" ];
            };
            runtimeTarget.advertisements.dhcp4 = [
              {
                id = "client-v4";
                enabled = true;
                interface = "tenant-client";
                tenant = "client";
                subnet = "10.20.20.0/24";
                pool = "10.20.20.100 - 10.20.20.199";
                router = "10.20.20.1";
                reservations = [
                  {
                    id = "public-descriptor";
                    address = "10.20.20.10";
                    identitySource = {
                      sourceClass = "protected";
                      sourceFile = "/run/secrets/s-router-prod-vlan2-reservations.json";
                    };
                  }
                ];
              }
            ];
          };
        };
    in
      builtins.deepSeq model true
  ' >"${tmp}/per-record.out" 2>"${per_record_err}"; then
  fail "FAIL runtime-secret-reservation-materialization: per-record protected runtime source was accepted"
fi
grep -F "diagnostic.runtime-reservation-source-must-be-scope-level" "${per_record_err}" >/dev/null || {
  cat "${per_record_err}" >&2
  fail "FAIL runtime-secret-reservation-materialization: per-record source did not emit the scope-level diagnostic"
}

pass "runtime-secret-reservation-materialization per-record source rejected"

echo "PASS FS-970-HDS-010-SDS-020-SMS-040-runtime-secret-reservation-materialization"
