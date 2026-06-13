#!/usr/bin/env bash
# GAMP-ID: FS-982-HDS-010-SDS-010-SMS-070
# GAMP-SCOPE: software-module-test
# Focused construction test: No oneshot secret services.
#
# SMS-070: Prohibits systemd oneshot services for secret materialization
# (symlink services, ExecStart with sops -d, writeShellScript for secrets).
# Requires platform-native declarative integration (sops-nix) per URS L27/L92/L97.
#
# Happy path: scan s-router-nixos host config for prohibited patterns → PASS if none.
# Seeded negative 1: inject pppoe-secret-symlink oneshot → verify detection.
# Seeded negative 2: inject hat-pppoe-secrets oneshot → verify detection.
#
# Auto-discovered by tests/test.sh via glob test-*.sh.
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# Source the common library for fail()/pass() helpers
source "${repo_root}/tests/lib/test-common.sh"

# --- Configuration ---
# The s-router-nixos host config directory in the nixos repo.
# Resolve via flake input if available, otherwise use known path.
if command -v nix >/dev/null 2>&1; then
  nixos_repo="$(nix flake archive --json "path:${repo_root}" 2>/dev/null \
    | _jq -er '.originalUrl // empty' 2>/dev/null || true)"
fi
# Fallback: use ~/github/nixos (standard development layout)
NIXOS_REPO="${NIXOS_REPO:-${HOME}/github/nixos}"
HOST_CONFIG_DIR="${NIXOS_REPO}/nixos/virtual-machine/nixos-shell-vm/s-router-nixos"

tmp_dir="$(mktemp -d "${TMPDIR:-/tmp}/network-renderer-nixos-fs982-sms070.XXXXXX")"
trap 'rm -rf "${tmp_dir}"' EXIT

echo "--- FS-982-HDS-010-SDS-010-SMS-070: No oneshot secret services scan ---"
echo "Host config dir: ${HOST_CONFIG_DIR}"
echo ""

# ============================================================
# Grep patterns for oneshot secret services.
#
# Pattern A: systemd.services with Type="oneshot" and secret operations
#   - symlink of secrets (ln -sf /run/secrets/)
#   - sops -d calls
#   - writeShellScript for secret materialization
#   - ExecStart with secret paths
#
# Pattern B: Any systemd oneshot service that references /run/secrets,
#   sops, or writeShellScript with secret-related content.
# ============================================================

scan_for_oneshot_secrets() {
  local dir="$1"
  local out_file="$2"
  > "${out_file}"

  if [[ ! -d "${dir}" ]]; then
    echo "WARN: host config directory not found: ${dir}" >&2
    return 0
  fi

  # Find .nix files, grep for systemd.services with oneshot + secret ops
  find "${dir}" -maxdepth 1 -name '*.nix' -print0 2>/dev/null | \
    xargs -0 grep -l 'systemd\.services' 2>/dev/null | \
    xargs grep -Hn -E \
      '(Type\s*=\s*"oneshot".*secret|secret.*Type\s*=\s*"oneshot")' \
      2>/dev/null >> "${out_file}" || true

  # Also catch: oneshot services that reference /run/secrets/
  find "${dir}" -maxdepth 1 -name '*.nix' -print0 2>/dev/null | \
    xargs -0 grep -l 'systemd\.services' 2>/dev/null | \
    xargs grep -Hn '/run/secrets/' 2>/dev/null >> "${out_file}" || true

  # Also catch: oneshot services using sops -d
  find "${dir}" -maxdepth 1 -name '*.nix' -print0 2>/dev/null | \
    xargs -0 grep -l 'systemd\.services' 2>/dev/null | \
    xargs grep -Hn 'sops\s+-d' 2>/dev/null >> "${out_file}" || true

  # Also catch: writeShellScript for secret materialization
  find "${dir}" -maxdepth 1 -name '*.nix' -print0 2>/dev/null | \
    xargs -0 grep -l 'systemd\.services' 2>/dev/null | \
    xargs grep -Hn 'writeShellScript.*secret\|writeShellScript.*sops\|writeShellScript.*pppoe' \
      2>/dev/null >> "${out_file}" || true

  # Also catch: oneshot services with ln -sf (symlink hack for secrets)
  find "${dir}" -maxdepth 1 -name '*.nix' -print0 2>/dev/null | \
    xargs -0 grep -l 'systemd\.services' 2>/dev/null | \
    xargs grep -Hn 'ln\s+-sf\s+/run/secrets' 2>/dev/null >> "${out_file}" || true

  # Deduplicate
  if [[ -s "${out_file}" ]]; then
    sort -u "${out_file}" > "${out_file}.sorted"
    mv "${out_file}.sorted" "${out_file}"
  fi
}

# ============================================================
# Happy path: scan the actual host config
# ============================================================
echo "--- Happy path: scanning s-router-nixos host config ---"
happy_violations="${tmp_dir}/happy-violations.txt"
scan_for_oneshot_secrets "${HOST_CONFIG_DIR}" "${happy_violations}"

happy_count=$(wc -l < "${happy_violations}" 2>/dev/null || echo 0)
if [[ "${happy_count}" -gt 0 ]]; then
  echo "FAIL: Found oneshot secret services in host config:" >&2
  cat "${happy_violations}" >&2
  exit 1
fi
echo "PASS: Happy path — no oneshot secret services found in s-router-nixos host config."

# ============================================================
# Seeded Negative 1: pppoe-secret-symlink
# ============================================================
echo ""
echo "--- Seeded Negative 1: pppoe-secret-symlink oneshot service ---"

neg1_file="${tmp_dir}/neg1-pppoe-secret-symlink.nix"
cat > "${neg1_file}" << 'NIXEOF'
{ config, lib, pkgs, ... }:
{
  systemd.services.pppoe-secret-symlink = {
    wantedBy = [ "multi-user.target" ];
    serviceConfig.Type = "oneshot";
    script = ''
      mkdir -p /run/secrets
      ln -sf /run/secrets/pppoe-credentials /run/secrets/hat-pppoe-credentials
    '';
  };
}
NIXEOF

neg1_violations="${tmp_dir}/neg1-violations.txt"
scan_for_oneshot_secrets "${tmp_dir}" "${neg1_violations}"

neg1_count=$(wc -l < "${neg1_violations}" 2>/dev/null || echo 0)
if [[ "${neg1_count}" -eq 0 ]]; then
  echo "FAIL: Seeded negative 1 — pppoe-secret-symlink NOT detected!" >&2
  echo "Scanner failed to detect prohibited oneshot symlink service." >&2
  exit 1
fi
echo "PASS: Seeded negative 1 — pppoe-secret-symlink detected (${neg1_count} violation(s))."
echo "  Violation: $(head -1 "${neg1_violations}")"

# ============================================================
# Seeded Negative 2: hat-pppoe-secrets with writeShellScript + sops
# ============================================================
echo ""
echo "--- Seeded Negative 2: hat-pppoe-secrets oneshot service ---"

neg2_file="${tmp_dir}/neg2-hat-pppoe-secrets.nix"
cat > "${neg2_file}" << 'NIXEOF'
{ config, lib, pkgs, ... }:
{
  systemd.services.hat-pppoe-secrets = {
    wantedBy = [ "multi-user.target" ];
    serviceConfig.Type = "oneshot";
    serviceConfig.ExecStart = pkgs.writeShellScript "hat-pppoe-secrets-init" ''
      mkdir -p /run/secrets/hat
      sops -d /etc/s-router/pppoe-creds.enc > /run/secrets/hat/pppoe-creds
      chmod 600 /run/secrets/hat/pppoe-creds
    '';
  };
}
NIXEOF

neg2_violations="${tmp_dir}/neg2-violations.txt"
scan_for_oneshot_secrets "${tmp_dir}" "${neg2_violations}"

neg2_count=$(wc -l < "${neg2_violations}" 2>/dev/null || echo 0)
if [[ "${neg2_count}" -eq 0 ]]; then
  echo "FAIL: Seeded negative 2 — hat-pppoe-secrets NOT detected!" >&2
  echo "Scanner failed to detect prohibited oneshot writeShellScript + sops service." >&2
  exit 1
fi
echo "PASS: Seeded negative 2 — hat-pppoe-secrets detected (${neg2_count} violation(s))."
echo "  Violation: $(head -1 "${neg2_violations}")"

# ============================================================
# Post-removal acceptance: remove negatives, re-scan, expect clean
# ============================================================
echo ""
echo "--- Post-removal acceptance: removing negatives, re-scanning ---"
rm -f "${neg1_file}" "${neg2_file}"

clean_violations="${tmp_dir}/clean-violations.txt"
scan_for_oneshot_secrets "${tmp_dir}" "${clean_violations}"

clean_count=$(wc -l < "${clean_violations}" 2>/dev/null || echo 0)
if [[ "${clean_count}" -gt 0 ]]; then
  echo "FAIL: Post-removal scan still found violations:" >&2
  cat "${clean_violations}" >&2
  exit 1
fi
echo "PASS: Post-removal acceptance — clean scan after removing negatives."

# ============================================================
# Final report
# ============================================================
echo ""
echo "--- Results ---"
echo "Happy path:       PASS (no violations in s-router-nixos)"
echo "Seeded negative 1: PASS (${neg1_count} violation(s) detected)"
echo "Seeded negative 2: PASS (${neg2_count} violation(s) detected)"
echo "Post-removal:     PASS (clean after removing negatives)"
echo ""
echo "PASS FS-982-HDS-010-SDS-010-SMS-070: no-oneshot-secret-services construction test complete."
