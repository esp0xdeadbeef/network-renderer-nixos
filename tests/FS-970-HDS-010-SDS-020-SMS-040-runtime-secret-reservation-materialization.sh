#!/usr/bin/env bash
# GAMP-ID: FS-970-HDS-010-SDS-020-SMS-040
# GAMP-SCOPE: software-module-test
#
# Runtime Secret DHCPv4 Reservation Materialization — NixOS renderer construction
# evidence. Proves the renderer:
#   - accepts source-file-backed DHCPv4 reservation records from CPM
#   - emits a read-only /run/secrets/... reservation source bind mount into the
#     container that runs Kea
#   - materializes Kea reservations at runtime (not at Nix eval), matching the
#     CPM-resolved reservation to a record in the protected source file
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
# Positive case: renderer accepts a source-file-backed reservation, emits a
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
  reservations = [
    {
      id = "printer-reservation-10";
      address = "10.20.20.10";
      cidr = "10.20.20.10/32";
      hostOffset = 10;
      identitySource = {
        sourceClass = "protected";
        sourceFile = "/run/secrets/s-router-prod-vlan2-reservations.json";
      };
    }
  ];
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

kea_gen_drv="$(
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
        kea.systemd.services.\"gen-kea-client-v4\".serviceConfig.ExecStart.drvPath
    "
)"

nix-store -r "$kea_gen_drv" >/dev/null

# Runtime materialization script must exist and be runtime (reads source file,
# matches CPM-resolved address, mutates the runtime cfg after eval/build).
grep -F "$source_file" "$kea_gen_script" >/dev/null \
  || fail "FAIL runtime-secret-reservation-materialization: gen script does not reference the runtime secret source file"
grep -F 'subnet4[0].reservations' "$kea_gen_script" >/dev/null \
  || fail "FAIL runtime-secret-reservation-materialization: gen script does not materialize runtime reservations into subnet4"
grep -F 'diagnostic.runtime-reservation-secret-record-invalid' "$kea_gen_script" >/dev/null \
  || fail "FAIL runtime-secret-reservation-materialization: gen script does not carry NC4 diagnostic token"

# Protected value leak (NC5): neither the generated non-secret gen script nor
# the static config embedded in it may contain the protected MAC or the private
# hostname; those come only from the runtime secret at runtime.
if grep -F "$protected_mac" "$kea_gen_script" >/dev/null; then
  fail "FAIL runtime-secret-reservation-materialization: NC5 protected MAC leaked into generated non-secret gen script"
fi
if grep -F "$protected_hostname" "$kea_gen_script" >/dev/null; then
  fail "FAIL runtime-secret-reservation-materialization: NC5 protected hostname leaked into generated non-secret gen script"
fi

pass "runtime-secret-reservation-materialization positive + NC5 (gen script)"

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
              reservations = [
                {
                  id = "printer-reservation-10";
                  address = "10.20.20.10";
                  cidr = "10.20.20.10/32";
                  hostOffset = 10;
                  identitySource = {
                    sourceClass = "protected";
                    sourceFile = "/run/secrets/s-router-prod-vlan2-reservations.json";
                  };
                }
              ];
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
# NC3 - unapproved runtime source path: a reservation whose identitySource
# sourceFile is not under /run/secrets/ shall be rejected by the renderer
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
                reservations = [
                  {
                    id = "unapproved-path";
                    address = "10.20.20.10";
                    identitySource = {
                      sourceClass = "protected";
                      sourceFile = "/etc/kea/unapproved-reservations.json";
                    };
                  }
                ];
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

echo "PASS FS-970-HDS-010-SDS-020-SMS-040-runtime-secret-reservation-materialization"
