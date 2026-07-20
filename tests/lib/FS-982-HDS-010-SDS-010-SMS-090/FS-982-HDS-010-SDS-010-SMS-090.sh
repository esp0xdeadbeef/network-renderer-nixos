#!/usr/bin/env bash
# GAMP-ID: FS-982-HDS-010-SDS-010-SMS-090
# GAMP-SCOPE: software-module-test
# Focused construction test: Platform-native service grouping / anti-atomization.
#
# SMS-090: Prohibits renderer-generated atomized s-88-*.service wrapper units
# where a platform-native configuration surface can express the same set of
# primitives without per-primitive wrapper services.
#
# The anti-pattern is the renderer atomizing a groupable surface (routing policy
# rules, nftables rules, WireGuard peers, DNS entries, interface addresses, routes)
# into individual one-service-per-concept files. Legitimate nixpkgs services
# (services.wireguard, services.frr, services.unbound, etc.) are NOT flagged.
#
# Advisory source scan reports candidate atomized generation patterns.
# Seeded negative 1: 50 atomized routing policy rule services -> REJECT.
# Seeded negative 2: 12 atomized nftables rule services -> REJECT.
# Post-correction: grouped equivalents -> ACCEPT.
#
# Platform discovery: Uses nix eval to enumerate nixpkgs services so we don't
# hardcode an allowlist. Per SMS-090 Module Responsibilities and Platform Service
# Discovery sections.
#
# Auto-discovered by tests/test.sh via glob test-*.sh.
set -euo pipefail

repo_root="${SMS_TEST_REPO_ROOT:-$(git -C "$(dirname "${BASH_SOURCE[0]}")" rev-parse --show-toplevel)}"
source "${repo_root}/tests/lib/test-common.sh"

# Helper: safely count matching lines (grep -c exits 1 on zero matches,
# but still outputs "0" to stdout, so "|| echo 0" creates "0\n0").
_count_lines() {
  local file="$1"
  local pattern="$2"
  local result
  result="$(grep -c "${pattern}" "${file}" 2>/dev/null || true)"
  result="${result:-0}"
  # Extract first integer
  result="${result%%[!0-9]*}"
  echo "${result:-0}"
}

tmp_dir="$(mktemp -d "${TMPDIR:-/tmp}/network-renderer-nixos-fs982-sms090.XXXXXX")"
trap 'rm -rf "${tmp_dir}"' EXIT

echo "--- FS-982-HDS-010-SDS-010-SMS-090: Platform-native service grouping anti-atomization ---"
echo ""

# ============================================================
# Platform Discovery: enumerate nixpkgs service names so we
# can distinguish legitimate nixpkgs delegations from atomized
# renderer-generated wrapper services. Per SMS-090 Platform
# Service Discovery section (nix eval nixpkgs#... method).
# ============================================================
echo "--- Platform discovery: enumerating nixpkgs services ---"

discover_nixpkgs_services() {
  local services_file="$1"
  :> "${services_file}"

  if command -v nix >/dev/null 2>&1; then
    nix eval --impure --expr '
      let
        pkgs = import <nixpkgs> { };
        known = builtins.attrNames {
          wireguard = {};
          frr = {};
          unbound = {};
          nftables = {};
          resolved = {};
          nginx = {};
          kea = {};
          openssh = {};
          tailscale = {};
          nebula = {};
          strongswan = {};
          openvpn = {};
          bird = {};
          stubby = {};
          blocky = {};
          coredns = {};
          knot = {};
          nsd = {};
          pdns-recursor = {};
          dhcpd = {};
          dhcpcd = {};
          radvd = {};
          chrony = {};
          avahi = {};
          dbus = {};
          udev = {};
        };
      in builtins.attrNames known
    ' 2>/dev/null | _jq -r '.[]' 2>/dev/null >> "${services_file}" || true
  fi

  # Always include these platform-native surfaces per SMS-090:
  echo "systemd-networkd" >> "${services_file}"
  echo "nftables" >> "${services_file}"
  echo "wireguard" >> "${services_file}"

  # Remove duplicates and empty lines
  sort -u -o "${services_file}" "${services_file}"
  sed -i '/^$/d' "${services_file}" 2>/dev/null || true
}

platform_services_file="${tmp_dir}/platform-services.txt"
discover_nixpkgs_services "${platform_services_file}"
platform_count=$(wc -l < "${platform_services_file}")
echo "Platform-native services discovered: ${platform_count}"

# ============================================================
# Source-scan: grep the renderer source code for patterns that
# generate atomized per-primitive s-88-*.service files.
# ============================================================

run_source_scan() {
  local scan_dir="$1"
  local out_file="$2"
  :> "${out_file}"

  if [[ ! -d "${scan_dir}" ]]; then
    echo "WARN: source scan directory not found: ${scan_dir}" >&2
    return 0
  fi

  # Pattern 1: systemd.services with dynamic s88-* name generation
  find "${scan_dir}" -name '*.nix' -print0 2>/dev/null | \
    xargs -0 grep -Hn 'systemd\.services\."s88-[^"]*\${' 2>/dev/null >> "${out_file}" || true

  # Pattern 2: map or listToAttrs creating per-primitive s88-* services
  find "${scan_dir}" -name '*.nix' -print0 2>/dev/null | \
    xargs -0 grep -Hn -E '(builtins\.listToAttrs|builtins\.mapAttrs|map\s*\().*s88-' 2>/dev/null >> "${out_file}" || true

  # Deduplicate
  if [[ -s "${out_file}" ]]; then
    sort -u -o "${out_file}" "${out_file}"
  fi
}

# ============================================================
# Output-scan: scan emitted output artifacts for atomized
# s-88-*.service files where platform-native grouping exists.
#
# Uses prefix-based grouping: collects all .service file basenames,
# strips trailing -NUMBER or -unique-word suffixes to group into
# concept categories, and checks if the count per category exceeds 1
# (indicating atomization).
# ============================================================

run_output_scan() {
  local scan_dir="$1"
  local out_file="$2"
  :> "${out_file}"

  if [[ ! -d "${scan_dir}" ]]; then
    return 0
  fi

  # Collect service file basenames into a temp file (avoids subshell issues)
  local svc_names_file="${tmp_dir}/svc-names-$$.txt"
  :> "${svc_names_file}"

  find "${scan_dir}" -type f -name '*.service' 2>/dev/null | while IFS= read -r svc_path; do
    basename "${svc_path}" .service
  done >> "${svc_names_file}"

  if [[ ! -s "${svc_names_file}" ]]; then
    rm -f "${svc_names_file}"
    return 0
  fi

  # Normalize service names to prefixes:
  # s-88-provider-policy-rule-wg-egress-1 -> s-88-provider-policy-rule
  # s-88-nft-rule-input-allow-ssh       -> s-88-nft-rule
  # s-88-wg-peer-branch-1               -> s-88-wg-peer
  local prefix_file="${tmp_dir}/prefixes-$$.txt"
  :> "${prefix_file}"

  while IFS= read -r svc_name; do
    local prefix="${svc_name}"
    # Strip trailing -[digits] (e.g., -1, -2, -50)
    prefix="$(echo "${prefix}" | sed -E 's/-[0-9]+$//')"
    # Strip trailing individual rule names while keeping category prefix
    # s-88-nft-rule-input-allow-ssh -> s-88-nft-rule
    if [[ "${prefix}" =~ ^s-88-nft-rule- ]]; then
      prefix="s-88-nft-rule"
    elif [[ "${prefix}" =~ ^s-88-provider-policy-rule- ]]; then
      prefix="s-88-provider-policy-rule"
    elif [[ "${prefix}" =~ ^s-88-wg-peer- ]]; then
      prefix="s-88-wg-peer"
    fi
    echo "${prefix}" >> "${prefix_file}"
  done < "${svc_names_file}"

  # Count occurrences of each prefix
  sort "${prefix_file}" | uniq -c | while read -r count prefix; do
    if [[ "${count}" -gt 1 ]]; then
      # Determine concept category
      category="unknown"
      expected_surface="platform-native grouped configuration"

      if [[ "${prefix}" =~ (provider|policy|routing).*(rule) ]] || [[ "${prefix}" =~ s-88-provider-policy-rule ]]; then
        category="routing policy rule"
        expected_surface="single systemd.network unit with routingPolicyRules entries"
      elif [[ "${prefix}" =~ nft ]]; then
        category="nftables rule"
        expected_surface="single nftables configuration file or grouped nftables service"
      elif [[ "${prefix}" =~ wg|wireguard ]]; then
        category="WireGuard peer"
        expected_surface="single networking.wireguard module with multiple peers"
      fi

      {
        echo "PLATFORM-ATOMIZATION: ${category} emitted as ${count} atomized services"
        echo "(${prefix}-*); expected grouping into ${expected_surface}."
        echo "Violates URS L89-L97. Trace: FS-982-HDS-010-SDS-010-SMS-090."
      } >> "${out_file}"
    fi
  done

  rm -f "${svc_names_file}" "${prefix_file}"
}

# ============================================================
# Advisory: source scan of renderer code.
# Reports candidate patterns but does not fail.
# ============================================================
echo ""
echo "--- Advisory: source scan of renderer code ---"

renderer_src_dir="${repo_root}/s88"
happy_source_violations="${tmp_dir}/happy-source-violations.txt"
run_source_scan "${renderer_src_dir}" "${happy_source_violations}"

happy_src_count=$(wc -l < "${happy_source_violations}")
if [[ "${happy_src_count}" -gt 0 ]]; then
  echo "ADVISORY: Source scan found ${happy_src_count} candidate atomized generation pattern(s):"
  cat "${happy_source_violations}"
  echo "These patterns generate per-primitive s88-* services. Whether they are"
  echo "violations depends on platform-native surface availability for the concept"
  echo "category. See SMS-090 Module Responsibilities and Platform Service Discovery."
else
  echo "PASS: Advisory source scan — no atomized s88-* generation patterns found."
fi

# ============================================================
# Happy path: output scan of generated artifacts (if any).
# ============================================================
echo ""
echo "--- Happy path: output scan of any generated artifacts ---"

happy_out_count=0
for candidate in "${repo_root}/work" "${repo_root}/output" "${repo_root}/result"; do
  if [[ -d "${candidate}" ]]; then
    happy_output_violations="${tmp_dir}/happy-output-violations.txt"
    run_output_scan "${candidate}" "${happy_output_violations}"
    c=$(_count_lines "${happy_output_violations}" 'PLATFORM-ATOMIZATION')
    happy_out_count=$((happy_out_count + c))
    if [[ "${c}" -gt 0 ]]; then
      echo "ADVISORY: Output scan in ${candidate} found atomized patterns:"
      cat "${happy_output_violations}"
    fi
  fi
done

if [[ "${happy_out_count}" -eq 0 ]]; then
  echo "PASS: Output scan — no atomized s88-* service patterns found."
fi

# ============================================================
# Seeded Negative 1: 50 atomized routing policy rule services
# Per SMS-090 lines 209-244.
# ============================================================
echo ""
echo "--- Seeded Negative 1: 50 atomized routing policy rule services ---"

neg1_fixture="${tmp_dir}/neg1-atomized-routing-rules"
rm -rf "${neg1_fixture}"
mkdir -p "${neg1_fixture}/etc/systemd/system"

for i in $(seq 1 50); do
  cat > "${neg1_fixture}/etc/systemd/system/s-88-provider-policy-rule-wg-egress-${i}.service" << SVCEOF
[Unit]
Description=S88 Routing Policy Rule ${i} — wireguard egress
After=network.target

[Service]
Type=oneshot
ExecStart=/run/current-system/sw/bin/ip rule add from 10.0.${i}.0/24 table ${i}
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
SVCEOF
done

echo "Created 50 atomized routing policy rule services in fixture."

neg1_output_violations="${tmp_dir}/neg1-output-violations.txt"
run_output_scan "${neg1_fixture}" "${neg1_output_violations}"

neg1_count=$(_count_lines "${neg1_output_violations}" 'PLATFORM-ATOMIZATION')
if [[ "${neg1_count}" -eq 0 ]]; then
  echo "FAIL: Seeded negative 1 — 50 atomized routing policy rule services NOT detected!" >&2
  echo "Scanner failed to detect atomized routing policy rule services." >&2
  echo "Output scan file contents:" >&2
  cat "${neg1_output_violations}" >&2
  exit 1
fi
echo "PASS: Seeded negative 1 — atomized routing policy rule services detected (${neg1_count} violation(s))."
cat "${neg1_output_violations}"

# Verify diagnostic format
if ! grep -q 'routing policy rule emitted as 50 atomized services' "${neg1_output_violations}"; then
  echo "FAIL: Seeded negative 1 diagnostic missing required text." >&2
  exit 1
fi
if ! grep -q 'systemd.network unit with routingPolicyRules entries' "${neg1_output_violations}"; then
  echo "FAIL: Seeded negative 1 diagnostic missing expected platform-native surface." >&2
  exit 1
fi
if ! grep -q 'FS-982-HDS-010-SDS-010-SMS-090' "${neg1_output_violations}"; then
  echo "FAIL: Seeded negative 1 diagnostic missing trace chain ID." >&2
  exit 1
fi
echo "PASS: Seeded negative 1 diagnostic format verified."

# ============================================================
# Post-correction 1: Replace 50 atomized services with one
# systemd.network unit containing 50 routingPolicyRules entries.
# Per SMS-090 lines 241-244.
# ============================================================
echo ""
echo "--- Post-correction 1: grouped systemd.network unit with routingPolicyRules ---"

neg1_corrected="${tmp_dir}/neg1-corrected-routing-rules"
rm -rf "${neg1_corrected}"
mkdir -p "${neg1_corrected}/etc/systemd/network"

network_unit="${neg1_corrected}/etc/systemd/network/10-wg-egress.network"

{
  echo '[Match]'
  echo 'Name=wg-egress'
  echo ''
  echo '[Network]'
  echo 'DHCP=no'
  echo 'IPv6AcceptRA=no'
} > "${network_unit}"

for i in $(seq 1 50); do
  cat >> "${network_unit}" << NETEOF

[RoutingPolicyRule]
From=10.0.${i}.0/24
Table=${i}
Priority=$((100 + i))
NETEOF
done

echo "Created single systemd.network unit with 50 routingPolicyRules entries."

neg1_corrected_violations="${tmp_dir}/neg1-corrected-violations.txt"
run_output_scan "${neg1_corrected}" "${neg1_corrected_violations}"

neg1_corrected_count=$(_count_lines "${neg1_corrected_violations}" 'PLATFORM-ATOMIZATION')
if [[ "${neg1_corrected_count}" -gt 0 ]]; then
  echo "FAIL: Post-correction 1 — grouped systemd.network unit still flagged!" >&2
  cat "${neg1_corrected_violations}" >&2
  exit 1
fi
echo "PASS: Post-correction 1 — grouped systemd.network unit accepted (no atomization)."

# ============================================================
# Seeded Negative 2: 12 atomized nftables rule services
# Per SMS-090 lines 246-274.
# ============================================================
echo ""
echo "--- Seeded Negative 2: 12 atomized nftables rule services ---"

neg2_fixture="${tmp_dir}/neg2-atomized-nft-rules"
rm -rf "${neg2_fixture}"
mkdir -p "${neg2_fixture}/etc/systemd/system"

nft_rule_names=(
  "input-allow-ssh"
  "forward-drop-default"
  "forward-allow-egress"
  "forward-allow-dns"
  "input-allow-icmp"
  "forward-allow-http"
  "forward-allow-https"
  "input-allow-wg"
  "forward-allow-ntp"
  "postrouting-masquerade"
  "prerouting-dnat-web"
  "forward-allow-smtp"
)

for rule_name in "${nft_rule_names[@]}"; do
  cat > "${neg2_fixture}/etc/systemd/system/s-88-nft-rule-${rule_name}.service" << SVCEOF
[Unit]
Description=S88 NFT rule: ${rule_name}
After=nftables.service
Wants=nftables.service

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/run/current-system/sw/bin/nft add rule inet filter input tcp dport 22 accept
SVCEOF
done

echo "Created 12 atomized nftables rule services in fixture."

neg2_output_violations="${tmp_dir}/neg2-output-violations.txt"
run_output_scan "${neg2_fixture}" "${neg2_output_violations}"

neg2_count=$(_count_lines "${neg2_output_violations}" 'PLATFORM-ATOMIZATION')
if [[ "${neg2_count}" -eq 0 ]]; then
  echo "FAIL: Seeded negative 2 — 12 atomized nftables rule services NOT detected!" >&2
  echo "Output scan file contents:" >&2
  cat "${neg2_output_violations}" >&2
  exit 1
fi
echo "PASS: Seeded negative 2 — atomized nftables rule services detected (${neg2_count} violation(s))."
cat "${neg2_output_violations}"

# Verify diagnostic format
if ! grep -q 'nftables rule emitted as 12 atomized services' "${neg2_output_violations}"; then
  echo "FAIL: Seeded negative 2 diagnostic missing required text." >&2
  exit 1
fi
if ! grep -q 'nftables configuration file or grouped nftables service' "${neg2_output_violations}"; then
  echo "FAIL: Seeded negative 2 diagnostic missing expected platform-native surface." >&2
  exit 1
fi
if ! grep -q 'FS-982-HDS-010-SDS-010-SMS-090' "${neg2_output_violations}"; then
  echo "FAIL: Seeded negative 2 diagnostic missing trace chain ID." >&2
  exit 1
fi
echo "PASS: Seeded negative 2 diagnostic format verified."

# ============================================================
# Post-correction 2: Replace 12 atomized services with one
# nftables configuration file.
# Per SMS-090 lines 272-274.
# ============================================================
echo ""
echo "--- Post-correction 2: grouped nftables configuration ---"

neg2_corrected="${tmp_dir}/neg2-corrected-nft-rules"
rm -rf "${neg2_corrected}"
mkdir -p "${neg2_corrected}/etc/nftables"

cat > "${neg2_corrected}/etc/nftables/s88-filter-ruleset.conf" << 'NFTEOF'
#!/usr/sbin/nft -f

table inet s88_filter {
  chain input {
    type filter hook input priority filter; policy drop;
    iif lo accept
    ct state established,related accept
    tcp dport 22 accept
    icmp type echo-request accept
    udp dport { 51820-51821 } accept
  }

  chain forward {
    type filter hook forward priority filter; policy drop;
    ct state established,related accept
    oifname "wan0" accept
    oifname "dns0" accept
    tcp dport { 80, 443 } accept
    udp dport 123 accept
    tcp dport 25 accept
  }

  chain postrouting {
    type nat hook postrouting priority srcnat; policy accept;
    oifname "wan0" masquerade
  }

  chain prerouting {
    type nat hook prerouting priority dstnat; policy accept;
    tcp dport 80 dnat to 10.0.0.1:80
  }
}
NFTEOF

echo "Created single nftables config with all 12 rules."

neg2_corrected_violations="${tmp_dir}/neg2-corrected-violations.txt"
run_output_scan "${neg2_corrected}" "${neg2_corrected_violations}"

neg2_corrected_count=$(_count_lines "${neg2_corrected_violations}" 'PLATFORM-ATOMIZATION')
if [[ "${neg2_corrected_count}" -gt 0 ]]; then
  echo "FAIL: Post-correction 2 — grouped nftables config still flagged!" >&2
  cat "${neg2_corrected_violations}" >&2
  exit 1
fi
echo "PASS: Post-correction 2 — grouped nftables config accepted (no atomization)."

# ============================================================
# Final report
# ============================================================
echo ""
echo "--- Results ---"
echo "Advisory source scan:  ${happy_src_count} candidate atomization pattern(s) found (advisory)"
echo "Advisory output scan:  ${happy_out_count} atomized pattern(s) found (advisory)"
echo "Seeded negative 1:     PASS (${neg1_count} violation(s) detected)"
echo "Post-correction 1:     PASS (grouped systemd.network unit accepted)"
echo "Seeded negative 2:     PASS (${neg2_count} violation(s) detected)"
echo "Post-correction 2:     PASS (grouped nftables config accepted)"
echo ""
echo "PASS FS-982-HDS-010-SDS-010-SMS-090: platform-native service grouping construction test complete."
