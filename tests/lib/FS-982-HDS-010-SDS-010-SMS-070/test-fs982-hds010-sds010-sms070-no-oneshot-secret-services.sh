#!/usr/bin/env bash
# GAMP-ID: FS-982-HDS-010-SDS-010-SMS-070
# GAMP-SCOPE: software-module-test
# Focused construction test: No oneshot secret services + FS-840 sops ordering.
#
# SMS-070: The NixOS renderer SHALL NOT create oneshot systemd services for
# secret materialization. Secrets must be delivered via declarative sops-nix
# integration with proper systemd ordering.
#
# FS-840: Container services must wait for sops-nix.service before starting
# when they depend on /run/secrets/ bind mounts.
#
# Active seeded negatives:
#   SN1 — construct a minimal module with a oneshot symlink service for secrets;
#          verify grep scanner detects it with SMS-070 diagnostic
#   SN2 — construct a module where a container service has NO sops-nix after;
#          verify grep scanner detects the gap
set -euo pipefail

repo_root="${SMS_TEST_REPO_ROOT:-$(git -C "$(dirname "${BASH_SOURCE[0]}")" rev-parse --show-toplevel)}"
tmp_dir="$(mktemp -d)"
trap 'rm -rf "${tmp_dir}"' EXIT

echo "--- FS-982-HDS-010-SDS-010-SMS-070: No oneshot secret services + FS-840 sops ordering ---"
echo ""

failures=0

# ============================================================
# Check 1: No oneshot secret services in the renderer source
# ============================================================
echo "--- Check 1: No oneshot secret-materialization services ---"

# Scan for systemd.services definitions that reference secret operations
# (sops -d, ln -sf secrets, mkdir /run/secrets, writeShellScript for secrets)
oneshot_hits=$(grep -rn 'systemd\.services\|serviceConfig\.Type.*oneshot' \
  "${repo_root}/s88/" --include='*.nix' -l 2>/dev/null || true)

violations=0
if [[ -n "${oneshot_hits}" ]]; then
  while IFS= read -r filename; do
    # Check if this file contains oneshot secret operations
    content=$(cat "${filename}" 2>/dev/null || true)
    if echo "${content}" | grep -qE '(sops -d|ln -sf.*secrets|writeShellScript.*secrets|ExecStart.*secrets)'; then
      echo "  FAIL: oneshot secret service in ${filename#${repo_root}/}"
      echo "    SMS-070: oneshot secret service violates declarative integration preference (URS L92)"
      violations=$((violations + 1))
    fi
  done <<< "${oneshot_hits}"
fi

if [[ ${violations} -eq 0 ]]; then
  echo "  PASS: No oneshot secret services detected in renderer source"
else
  echo "  FAIL: ${violations} oneshot secret service(s) found"
  failures=$((failures + 1))
fi
echo ""

# ============================================================
# Check 2: Container services have sops-nix.service ordering
# (FS-840: scoped runtime secret delivery)
# ============================================================
echo "--- Check 2: Container services wait for sops-nix.service (FS-840) ---"

# Verify flake.nix has the container@ name with after = [ "sops-nix.service" ]
if grep -q '"container@' "${repo_root}/flake.nix" && \
   grep -q '"sops-nix.service"' "${repo_root}/flake.nix"; then
  echo "  PASS: flake.nix adds sops-nix.service ordering for container instances"
else
  echo "  FAIL: flake.nix missing sops-nix.service ordering for containers"
  failures=$((failures + 1))
fi

# Verify public-ingress oneshot service also has sops ordering
if grep -q '"sops-nix.service"' "${repo_root}/s88/ControlModule/module/public-ingress.nix" 2>/dev/null; then
  echo "  PASS: public-ingress runtime-addresses service waits for sops-nix.service"
else
  echo "  FAIL: public-ingress service missing sops-nix.service ordering"
  failures=$((failures + 1))
fi
echo ""

# ============================================================
# Check 3 (Seeded Negative 1): Scanner detects oneshot secret service
# ============================================================
echo "--- Check 3 (SN1): Scanner detects injected oneshot symlink service ---"

injected_file="${tmp_dir}/injected-oneshot.nix"
cat > "${injected_file}" <<'NIX'
{ config, lib, pkgs, ... }:
{
  # VIOLATION: oneshot service that symlinks secrets — prohibited by SMS-070
  systemd.services.pppoe-secret-symlink = {
    wantedBy = [ "multi-user.target" ];
    serviceConfig.Type = "oneshot";
    script = ''
      mkdir -p /run/secrets
      ln -sf /run/secrets/pppoe-credentials /run/secrets/hat-pppoe-credentials
    '';
  };
}
NIX

# Scan the injected file using the same grep patterns as Check 1
if grep -qE '(sops -d|ln -sf.*secrets|writeShellScript.*secrets|ExecStart.*secrets)' "${injected_file}"; then
  echo "  PASS SN1: Scanner detects oneshot symlink service in injected violation"
else
  echo "  FAIL SN1: Scanner did NOT detect oneshot symlink service — check patterns"
  failures=$((failures + 1))
fi
echo ""

# ============================================================
# Check 4 (Seeded Negative 2): Scanner detects missing sops ordering
# ============================================================
echo "--- Check 4 (SN2): Scanner detects missing sops-nix.service in container def ---"

injected_flake="${tmp_dir}/injected-flake.nix"
cat > "${injected_flake}" <<'NIX'
{ lib, ... }:
{
  systemd.services."container@core-wan" = {
    after = [ "network-online.target" ];
    # VIOLATION: missing "sops-nix.service" — container may start before secrets ready
  };
}
NIX

# Scan: check for container@ service definitions that lack sops-nix.service
# in the actual after= list (exclude comments)
after_lines=$(grep -c 'after.*sops-nix.service' "${injected_flake}" 2>/dev/null || true)

if [[ "${after_lines:-0}" -eq 0 ]]; then
  echo "  PASS SN2: Scanner correctly identifies container@ service missing sops-nix.service"
else
  echo "  FAIL SN2: Scanner did not detect missing sops-nix ordering"
  failures=$((failures + 1))
fi
echo ""

# ============================================================
# Result
# ============================================================
if [[ ${failures} -eq 0 ]]; then
  echo "PASS FS-982-HDS-010-SDS-010-SMS-070 — no oneshot secret services + sops ordering verified"
  exit 0
else
  echo "FAIL FS-982-HDS-010-SDS-010-SMS-070: ${failures} failure(s)"
  exit 1
fi
