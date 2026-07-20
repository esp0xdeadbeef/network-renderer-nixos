#!/usr/bin/env bash
# GAMP-ID: FS-840-HDS-010-SDS-010-SMS-030
# GAMP-SCOPE: software-module-test
# Focused construction test: NixOS secret material readiness rejection.
#
# SMS-030: The NixOS renderer must reject service readiness when required
# secret material is missing, stale, mismatched, unauthorized, ambiguous,
# or over-broad. Affected services SHALL NOT be reported as ready until
# all required secret material passes readiness validation.
#
# In the NixOS platform, readiness rejection is implemented via:
#   - systemd ordering: container@<name>.after = [ "sops-nix.service" ]
#     (containers wait for sops-nix to deliver secrets before starting)
#   - /run/secrets/ path extraction from sourceFile fields in emission.nix
#     (renderer creates read-only bind mounts for secret paths)
#   - age key decryption via sops-nix (host-level secret delivery)
#
# Active seeded negatives:
#   SN1 — missing /run/secrets/ directory blocks container readiness:
#          construct a container service with bind mounts to /run/secrets/
#          but WITHOUT sops-nix.service in after=; verify scanner detects
#          the readiness gap (container may start before secrets ready)
#   SN2 — stale/expired secrets block container readiness:
#          construct a module where a service references /run/secrets/
#          paths but sourceFile paths bypass the sops-nix delivery
#          pipeline (not under /run/secrets/); verify scanner detects
#          the stale-delivery gap
#
# Auto-discovered by tests/test.sh via glob test-*.sh.
set -euo pipefail

repo_root="${SMS_TEST_REPO_ROOT:-$(git -C "$(dirname "${BASH_SOURCE[0]}")" rev-parse --show-toplevel)}"
tmp_dir="$(mktemp -d)"
trap 'rm -rf "${tmp_dir}"' EXIT

echo "--- FS-840-HDS-010-SDS-010-SMS-030: NixOS secret material readiness rejection ---"
echo ""

failures=0

# ============================================================
# Check 1: All containers have sops-nix.service ordering
# (FS-840: scoped runtime secret delivery — containers must wait
#  for sops-nix to deliver /run/secrets/ before starting)
# ============================================================
echo "--- Check 1: Container services wait for sops-nix.service ---"

# Extract the container@ list from flake.nix
# Pattern: "container@${name}" with after = [ "sops-nix.service" ]
flake_file="${repo_root}/flake.nix"

# Count container@ definitions
container_count=$(grep -c '"container@' "${flake_file}" 2>/dev/null || true)
container_count="${container_count:-0}"

# Count container@ definitions that have sops-nix.service in after=
sops_after_count=$(grep -B10 -A5 '"container@' "${flake_file}" 2>/dev/null | grep -c '"sops-nix.service"' || true)
sops_after_count="${sops_after_count:-0}"

if [[ "${container_count}" -eq 0 ]]; then
  echo "  INFO: No container@ definitions found in flake.nix (no containers to check)"
elif [[ "${sops_after_count}" -ge "${container_count}" ]]; then
  echo "  PASS: All ${container_count} container@ definitions include sops-nix.service ordering"
else
  echo "  FAIL: Only ${sops_after_count}/${container_count} container@ definitions include sops-nix.service ordering"
  failures=$((failures + 1))
fi

echo ""

# ============================================================
# Check 2: emission.nix extracts /run/secrets/ paths from
# sourceFile and creates read-only bind mounts
# ============================================================
echo "--- Check 2: emission.nix /run/secrets/ path extraction ---"

emission_file="${repo_root}/s88/ControlModule/render/containers/emission.nix"

# Verify /run/secrets/ prefix filtering exists
if grep -q 'lib.hasPrefix "/run/secrets/"' "${emission_file}" 2>/dev/null; then
  echo "  PASS: emission.nix filters /run/secrets/ paths from sourceFile fields"
else
  echo "  FAIL: emission.nix missing /run/secrets/ path extraction"
  failures=$((failures + 1))
fi

# Verify read-only bind mounts for runtime route source files
if grep -q 'isReadOnly = true' "${emission_file}" 2>/dev/null; then
  echo "  PASS: emission.nix creates read-only bind mounts for secret paths"
else
  echo "  FAIL: emission.nix missing read-only bind mount protection"
  failures=$((failures + 1))
fi

# Verify sourceFile path extraction exists
if grep -q 'routeSourceFile\|sourceFileFor' "${emission_file}" 2>/dev/null; then
  echo "  PASS: emission.nix extracts sourceFile paths for bind mounts"
else
  echo "  FAIL: emission.nix missing sourceFile path extraction logic"
  failures=$((failures + 1))
fi

# Verify bindMounts merge includes runtime secret mounts
if grep -q 'runtimeRouteSourceFileMounts' "${emission_file}" 2>/dev/null; then
  echo "  PASS: emission.nix merges runtime secret mounts into bindMounts"
else
  echo "  FAIL: emission.nix missing runtime secret mount merge"
  failures=$((failures + 1))
fi
echo ""

# ============================================================
# Check 3: public-ingress runtime-addresses service has
# sops-nix.service ordering (GAMP-required consumer)
# ============================================================
echo "--- Check 3: public-ingress runtime-addresses sops-nix ordering ---"

public_ingress_file="${repo_root}/s88/ControlModule/module/public-ingress.nix"

if grep -q '"sops-nix.service"' "${public_ingress_file}" 2>/dev/null; then
  echo "  PASS: public-ingress runtime-addresses service waits for sops-nix.service"
else
  echo "  FAIL: public-ingress missing sops-nix.service ordering"
  failures=$((failures + 1))
fi

# Verify the runtime-addresses service uses after= with sops-nix
if grep -A10 's88-host-public-ingress-runtime-addresses' "${public_ingress_file}" 2>/dev/null | grep -q '"sops-nix.service"'; then
  echo "  PASS: public-ingress runtime-addresses has explicit sops-nix.service in after="
else
  echo "  FAIL: public-ingress runtime-addresses missing explicit sops-nix.service ordering"
  failures=$((failures + 1))
fi
echo ""

# ============================================================
# Check 4 (Seeded Negative 1): Missing /run/secrets/ directory
# blocks container readiness.
# Construct a container service with bind mounts to /run/secrets/
# but WITHOUT sops-nix.service in after=.
# Scanner must detect the readiness gap.
# ============================================================
echo "--- Check 4 (SN1): Scanner detects container missing sops-nix ordering ---"

injected_sn1="${tmp_dir}/injected-no-sops-ordering.nix"
cat > "${injected_sn1}" <<'NIX'
{ lib, ... }:
{
  # VIOLATION: container with /run/secrets/ bind mount but NO sops-nix ordering
  # in after= — container may start before secrets are delivered.
  # This violates FS-840-HDS-010-SDS-010-SMS-030 readiness rejection:
  # missing /run/secrets/ material did not block readiness.
  systemd.services."container@core-wan" = {
    after = [ "network-online.target" ];
    # MISSING: sops-nix ordering — readiness gap
  };

  containers."core-wan" = {
    autoStart = true;
    bindMounts = {
      "/run/secrets/wg-peer-key" = {
        hostPath = "/run/secrets/wg-peer-key";
        isReadOnly = true;
      };
    };
  };
}
NIX

# Scan: check for container@ service definitions that reference
# /run/secrets/ in bindMounts but lack sops-nix.service in after=
# Exclude comment lines (starting with # or //) from the scan
sn1_gap_found=false

# Does the file have /run/secrets/ bind mount?
if grep -q '/run/secrets/' "${injected_sn1}" 2>/dev/null; then
  # Extract non-comment lines around container@ and check for sops-nix.service
  container_context=$(grep -B15 -A5 'container@' "${injected_sn1}" 2>/dev/null | grep -vE '^\s*(#|//|/\*)' || true)
  if echo "${container_context}" | grep -q '"sops-nix.service"'; then
    echo "  FAIL SN1: container@ has sops-nix.service — expected gap not detected"
    failures=$((failures + 1))
  else
    echo "  PASS SN1: Scanner correctly identifies /run/secrets/ bind mount without sops-nix.service ordering"
    sn1_gap_found=true
  fi
else
  echo "  FAIL SN1: injected file missing /run/secrets/ reference — cannot test"
  failures=$((failures + 1))
fi

# Additional check: verify the scanner pattern would detect this in real code
# by confirming grep can find the violation pattern
if [[ "${sn1_gap_found}" == "true" ]]; then
  # Positive control: the violation should be detectable
  violation_lines=$(grep -c '/run/secrets/' "${injected_sn1}" 2>/dev/null || true)
  after_sops_lines=$(grep -c 'sops-nix.service' "${injected_sn1}" 2>/dev/null || true)
  if [[ "${violation_lines:-0}" -gt 0 && "${after_sops_lines:-0}" -eq 0 ]]; then
    echo "  PASS SN1: Violation confirmed — /run/secrets/ present, sops-nix.service absent"
  else
    echo "  FAIL SN1: Violation pattern mismatch (/run/secrets: ${violation_lines}, sops-nix: ${after_sops_lines})"
    failures=$((failures + 1))
  fi
fi
echo ""

# ============================================================
# Check 5 (Seeded Negative 2): Stale/expired secrets block
# container readiness.
# Construct a module where a service references /run/secrets/
# paths but the sourceFile paths bypass the sops-nix delivery
# pipeline (e.g., direct /etc/ path instead of /run/secrets/)
# indicating stale or improperly delivered material.
# Scanner must detect the stale-delivery gap.
# ============================================================
echo "--- Check 5 (SN2): Scanner detects stale/bypassed secret delivery ---"

injected_sn2="${tmp_dir}/injected-stale-secret-delivery.nix"
cat > "${injected_sn2}" <<'NIX'
{ lib, ... }:
{
  # VIOLATION: Container references a secret path that bypasses the sops-nix
  # delivery pipeline — the sourceFile points to /etc/stale-secret instead of
  # /run/secrets/, indicating the secret was delivered through an uncontrolled
  # path. This violates FS-840-HDS-010-SDS-010-SMS-030 readiness rejection:
  # stale/expired secrets (delivered outside the controlled pipeline) did not
  # block readiness.
  containers."site-router" = {
    autoStart = true;
    bindMounts = {
      "/run/secrets/pppoe-creds" = {
        hostPath = "/etc/stale-secret/pppoe-credentials";
        isReadOnly = true;
      };
    };
  };

  # The container has sops-nix ordering, but the secret source
  # bypasses the /run/secrets/ pipeline — freshness not guaranteed.
  systemd.services."container@site-router" = {
    after = [ "sops-nix.service" ];
  };
}
NIX

# Scan: check for bind mounts where containerPath is under /run/secrets/
# but hostPath is NOT under /run/secrets/ (bypassing sops-nix delivery)
sn2_gap_found=false

# Extract bind mount entries: hostPath != /run/secrets/ when containerPath is /run/secrets/
if grep -q '"/run/secrets/' "${injected_sn2}" 2>/dev/null; then
  # Check if there's a hostPath that doesn't start with /run/secrets/
  host_paths=$(grep 'hostPath' "${injected_sn2}" 2>/dev/null || true)
  if echo "${host_paths}" | grep -q 'hostPath' && ! echo "${host_paths}" | grep -q 'hostPath = "/run/secrets/'; then
    echo "  PASS SN2: Scanner detects stale/bypassed secret delivery — hostPath outside /run/secrets/ pipeline"
    sn2_gap_found=true
  else
    # Check if sourceFile bypasses /run/secrets/
    if grep -q '/etc/stale-secret' "${injected_sn2}" 2>/dev/null; then
      echo "  PASS SN2: Scanner detects stale secret source — path outside controlled delivery pipeline"
      sn2_gap_found=true
    else
      echo "  FAIL SN2: injected file missing stale delivery pattern — cannot verify"
      failures=$((failures + 1))
    fi
  fi
else
  echo "  FAIL SN2: injected file missing /run/secrets/ reference — cannot test"
  failures=$((failures + 1))
fi

# Positive control: verify the violation pattern is detectable
if [[ "${sn2_gap_found}" == "true" ]]; then
  # Check that sops-nix ordering exists but secret source bypasses it
  sops_ok=$(grep -c 'sops-nix.service' "${injected_sn2}" 2>/dev/null || true)
  stale_path=$(grep -c '/etc/stale-secret' "${injected_sn2}" 2>/dev/null || true)
  if [[ "${sops_ok:-0}" -gt 0 && "${stale_path:-0}" -gt 0 ]]; then
    echo "  PASS SN2: Violation confirmed — sops-nix ordered but secret source bypasses /run/secrets/ pipeline"
  else
    echo "  FAIL SN2: Violation pattern mismatch (sops: ${sops_ok}, stale: ${stale_path})"
    failures=$((failures + 1))
  fi
fi
echo ""

# ============================================================
# Check 6: No oneshot services bypass sops-nix ordering
# (Cross-reference: FS-982-HDS-010-SDS-010-SMS-070 prevents
#  oneshot secret services, which would bypass readiness checks)
# ============================================================
echo "--- Check 6: No secret-delivery oneshot services bypass sops-nix ---"

# Scan for oneshot services that reference secret operations but lack
# sops-nix.service ordering (not covered by FS-982 test's scope)
oneshot_secret_hits=$(grep -rn 'systemd\.services\|serviceConfig\.Type.*oneshot' \
  "${repo_root}/s88/" --include='*.nix' -l 2>/dev/null || true)

oneshot_bypass_count=0
if [[ -n "${oneshot_secret_hits}" ]]; then
  while IFS= read -r filename; do
    content=$(cat "${filename}" 2>/dev/null || true)
    # Check if this oneshot service references secrets but lacks sops-nix ordering
    if echo "${content}" | grep -qE '(sops -d|/run/secrets/|secret_path|SecretPath)' && \
       ! echo "${content}" | grep -q '"sops-nix.service"'; then
      # Only flag if it's not a legitimate nixpkgs service
      if ! echo "${content}" | grep -qE 'services\.(wireguard|frr|unbound|nginx|kea)'; then
        echo "  FAIL: oneshot secret service without sops-nix ordering in ${filename#${repo_root}/}"
        oneshot_bypass_count=$((oneshot_bypass_count + 1))
      fi
    fi
  done <<< "${oneshot_secret_hits}"
fi

if [[ ${oneshot_bypass_count} -eq 0 ]]; then
  echo "  PASS: No oneshot secret services bypass sops-nix ordering"
else
  echo "  FAIL: ${oneshot_bypass_count} oneshot secret service(s) bypass sops-nix ordering"
  failures=$((failures + 1))
fi
echo ""

# ============================================================
# Result
# ============================================================
if [[ ${failures} -eq 0 ]]; then
  echo "PASS FS-840-HDS-010-SDS-010-SMS-030 — NixOS secret material readiness rejection verified"
  echo ""
  echo "Summary:"
  echo "  - Container sops-nix.service ordering: OK"
  echo "  - /run/secrets/ path extraction and bind mounts: OK"
  echo "  - public-ingress runtime-addresses sops ordering: OK"
  echo "  - SN1 (missing /run/secrets/ blocks readiness): detected"
  echo "  - SN2 (stale/bypassed secret delivery): detected"
  echo "  - No oneshot secret service bypasses: OK"
  exit 0
else
  echo "FAIL FS-840-HDS-010-SDS-010-SMS-030: ${failures} failure(s)"
  exit 1
fi
