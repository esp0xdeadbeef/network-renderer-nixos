#!/usr/bin/env bash
set -euo pipefail

family="${1:?address family is required}"
interface="${2:?interface name is required}"
port="${3:?UDP port is required}"
comment="${4:?rule comment is required}"

case "${family}" in
  ipv4 | ipv6) ;;
  *) printf 'invalid DHCP firewall family\n' >&2; exit 2 ;;
esac
[[ "${interface}" =~ ^[a-zA-Z0-9_.:-]+$ ]] || {
  printf 'invalid DHCP firewall interface\n' >&2
  exit 2
}
[[ "${port}" =~ ^[0-9]+$ ]] || {
  printf 'invalid DHCP firewall port\n' >&2
  exit 2
}
[[ "${comment}" =~ ^[a-zA-Z0-9_.:-]+$ ]] || {
  printf 'invalid DHCP firewall comment\n' >&2
  exit 2
}

if nft list chain inet router input | grep -Fq -- "${comment}"; then
  exit 0
fi

printf 'add rule inet router input meta nfproto %s iifname "%s" udp dport %s accept comment "%s"\n' \
  "${family}" "${interface}" "${port}" "${comment}" \
  | nft -f -
