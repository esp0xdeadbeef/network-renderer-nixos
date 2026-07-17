#!/usr/bin/env bash
# GAMP-ID: FS-970-HDS-010-SDS-020-SMS-040
# GAMP-SCOPE: software-module-test
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
tmp="$(mktemp -d)"
trap 'rm -rf "${tmp}"' EXIT

mkdir -p "${tmp}/bin" "${tmp}/operstate/tenant-client"
printf '#!/usr/bin/env bash\nexit 0\n' >"${tmp}/bin/ip"
printf '#!/usr/bin/env bash\nexit 0\n' >"${tmp}/bin/sleep"
# The generated fixture expands this value at runtime.
# shellcheck disable=SC2016
printf '#!/usr/bin/env bash\nif [[ "${FAKE_SS_LISTENER:-0}" == 1 ]]; then printf "listener\\n"; fi\n' >"${tmp}/bin/ss"
# The generated fixture expands these values at runtime.
# shellcheck disable=SC2016
printf '#!/usr/bin/env bash\nif [[ "$1" == list ]]; then [[ "${FAKE_NFT_RULE_PRESENT:-0}" == 1 ]] && printf "%%s\\n" "${FAKE_NFT_COMMENT:-}"; exit 0; fi\nif [[ "$1" == -f && "$2" == - ]]; then cat >"${FAKE_NFT_CAPTURE:?}"; exit 0; fi\nexit 1\n' >"${tmp}/bin/nft"
chmod +x "${tmp}/bin/ip" "${tmp}/bin/sleep" "${tmp}/bin/ss" "${tmp}/bin/nft"

printf 'down\n' >"${tmp}/operstate/tenant-client/operstate"
if PATH="${tmp}/bin:${PATH}" \
  OPERSTATE_ROOT="${tmp}/operstate" \
  WAIT_INTERFACE_ATTEMPTS=1 \
  bash "${repo_root}/s88/ControlModule/access/render/wait-interface-ready.sh" tenant-client \
  >/dev/null 2>&1; then
  echo "FAIL FS-970: administratively up interface without carrier was accepted" >&2
  exit 1
fi

printf 'up\n' >"${tmp}/operstate/tenant-client/operstate"
PATH="${tmp}/bin:${PATH}" \
  OPERSTATE_ROOT="${tmp}/operstate" \
  WAIT_INTERFACE_ATTEMPTS=1 \
  bash "${repo_root}/s88/ControlModule/access/render/wait-interface-ready.sh" tenant-client

if PATH="${tmp}/bin:${PATH}" \
  FAKE_SS_LISTENER=0 \
  KEA_LISTENER_ATTEMPTS=1 \
  bash "${repo_root}/s88/ControlModule/access/render/kea-listener-ready.sh" 547 \
  >/dev/null 2>&1; then
  echo "FAIL FS-970: missing DHCPv6 listener was accepted" >&2
  exit 1
fi

PATH="${tmp}/bin:${PATH}" \
  FAKE_SS_LISTENER=1 \
  KEA_LISTENER_ATTEMPTS=1 \
  bash "${repo_root}/s88/ControlModule/access/render/kea-listener-ready.sh" 547

if PATH="${tmp}/bin:${PATH}" \
  FAKE_NFT_CAPTURE="${tmp}/invalid-rule" \
  bash "${repo_root}/s88/ControlModule/access/render/allow-dhcp-service.sh" \
  ipv6 'tenant client' 547 allow-dhcp6-service-client >/dev/null 2>&1; then
  echo "FAIL FS-970: invalid DHCP service interface was accepted" >&2
  exit 1
fi
test ! -e "${tmp}/invalid-rule"

PATH="${tmp}/bin:${PATH}" \
  FAKE_NFT_CAPTURE="${tmp}/valid-rule" \
  bash "${repo_root}/s88/ControlModule/access/render/allow-dhcp-service.sh" \
  ipv6 tenant-client 547 allow-dhcp6-service-client
grep -Fx 'add rule inet router input meta nfproto ipv6 iifname "tenant-client" udp dport 547 accept comment "allow-dhcp6-service-client"' \
  "${tmp}/valid-rule" >/dev/null

echo "PASS FS-970 Kea interface and listener readiness"
