{ }:

''
  set -eu

  dns_query_ok() {
    qtype="$1"
    output="$(dig +time=2 +tries=1 @127.0.0.1 "$DNS_PROBE_NAME" "$qtype" 2>/dev/null || true)"
    printf "%s\n" "$output" | grep -q "status: NOERROR" \
      && printf "%s\n" "$output" | grep -Eq "[[:space:]]IN[[:space:]]+$qtype[[:space:]]"
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

  jq -n \
    --arg system_state "$system_state" \
    --argjson default4 "$default4" \
    --argjson default6 "$default6" \
    --argjson dns_service "$dns_service" \
    --arg dns4 "$dns4" \
    --arg dns6 "$dns6" \
    "{
      systemState: \$system_state,
      defaultRoute4: \$default4,
      defaultRoute6: \$default6,
      dnsService: \$dns_service,
      dnsA: \$dns4,
      dnsAAAA: \$dns6
    }"
''
