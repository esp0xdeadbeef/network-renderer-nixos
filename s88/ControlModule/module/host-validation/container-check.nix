{ }:

''
  set -eu

  dns_query_ok() {
    qtype="$1"
    output="$(dig +time=2 +tries=1 @127.0.0.1 "$DNS_PROBE_NAME" "$qtype" 2>/dev/null || true)"
    printf "%s\n" "$output" | grep -q "status: NOERROR" \
      && printf "%s\n" "$output" | grep -Eq "[[:space:]]IN[[:space:]]+$qtype[[:space:]]"
  }

  command_ok() {
    timeout_seconds="$1"
    shift
    timeout "$timeout_seconds" "$@" >/dev/null 2>&1
  }

  system_state="$(systemctl is-system-running 2>/dev/null || true)"

  if ip -4 route show default | grep -q .; then
    default4=true
  else
    default4=false
  fi

  if ip -6 route show default | grep -q .; then
    default6=true
  else
    default6=false
  fi

  if ip -4 route get "$PUBLIC_IPV4_PROBE" >/dev/null 2>&1; then
    route_get4=ok
  else
    route_get4=fail
  fi

  if ip -6 route get "$PUBLIC_IPV6_PROBE" >/dev/null 2>&1; then
    route_get6=ok
  else
    route_get6=fail
  fi

  if [ -f /etc/unbound/unbound.conf ]; then
    dns_service=true
    if dns_query_ok A; then
      dns4=ok
    else
      dns4=fail
    fi

    if dns_query_ok AAAA; then
      dns6=ok
    else
      dns6=fail
    fi
  else
    dns_service=false
    dns4=skip
    dns6=skip
  fi

  if command_ok 8 getent hosts "$DNS_PROBE_NAME"; then
    host_resolver=ok
  else
    host_resolver=fail
  fi

  if command_ok 8 ping -4 -c 1 "$PUBLIC_IPV4_PROBE"; then
    public_ipv4_ping=ok
  else
    public_ipv4_ping=fail
  fi

  if command_ok 8 ping -6 -c 1 "$PUBLIC_IPV6_PROBE"; then
    public_ipv6_ping=ok
  else
    public_ipv6_ping=fail
  fi

  jq -n \
    --arg system_state "$system_state" \
    --argjson default4 "$default4" \
    --argjson default6 "$default6" \
    --arg route_get4 "$route_get4" \
    --arg route_get6 "$route_get6" \
    --argjson dns_service "$dns_service" \
    --arg dns4 "$dns4" \
    --arg dns6 "$dns6" \
    --arg host_resolver "$host_resolver" \
    --arg public_ipv4_ping "$public_ipv4_ping" \
    --arg public_ipv6_ping "$public_ipv6_ping" \
    "{
      systemState: \$system_state,
      defaultRoute4: \$default4,
      defaultRoute6: \$default6,
      routeGet4: \$route_get4,
      routeGet6: \$route_get6,
      dnsService: \$dns_service,
      dnsA: \$dns4,
      dnsAAAA: \$dns6,
      hostResolver: \$host_resolver,
      publicIpv4Ping: \$public_ipv4_ping,
      publicIpv6Ping: \$public_ipv6_ping
    }"
''
