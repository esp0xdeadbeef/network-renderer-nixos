#!/usr/bin/env bash
set -eu

: "${LEASE_FILE:?}"
: "${NAMESPACE:?}"
: "${OWNER_SCOPE:?}"
: "${REQUESTER_SCOPE:?}"
: "${UNBOUND_CONTROL:?}"

[ -x "$UNBOUND_CONTROL" ] || exit 0
[ -s "$LEASE_FILE" ] || exit 0
"$UNBOUND_CONTROL" -c /etc/unbound/unbound.conf status >/dev/null 2>&1 || exit 0

awk -F, 'NR > 1 && $10 == "0" && $9 != "" { print $1 "\t" $9 }' "$LEASE_FILE" |
while IFS="$(printf '\t')" read -r address hostname; do
  case "$address:$hostname" in
    *[!A-Za-z0-9:._-]*|:*) continue ;;
  esac
  case "$hostname" in
    *.*) fqdn="$hostname" ;;
    *) fqdn="$hostname.$NAMESPACE" ;;
  esac
  case "$fqdn" in
    *.) ;;
    *) fqdn="$fqdn." ;;
  esac
  case "$fqdn" in
    *."$NAMESPACE") ;;
    *) continue ;;
  esac

  "$UNBOUND_CONTROL" -c /etc/unbound/unbound.conf local_data_remove "$fqdn" >/dev/null 2>&1 || true
  "$UNBOUND_CONTROL" -c /etc/unbound/unbound.conf local_data "$fqdn 60 IN A $address" >/dev/null 2>&1 || true
done
