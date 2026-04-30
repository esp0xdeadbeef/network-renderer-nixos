{ lib, pkgs }:

let
  checksAggregationFilter = pkgs.writeText "s88-network-validation-checks.jq" ''
    map({ (.key): .value }) | add
  '';

  containerCheck = import ./container-check.nix { };
in
pkgs.writeShellScript "s88-network-validation-loop" ''
  set -euo pipefail

  export PATH=${
    lib.makeBinPath [
      pkgs.bash
      pkgs.coreutils
      pkgs.gnugrep
      pkgs.gnused
      pkgs.jq
      pkgs.systemd
      pkgs.util-linux
    ]
  }

  state_dir=/run/s88-network-validation
  mkdir -p "$state_dir"

  plan=/etc/s88-network-validation/plan.json
  status_json="$state_dir/status.json"
  stable_json="$state_dir/stable.json"
  last_hash_file="$state_dir/last.hash"
  stable_count_file="$state_dir/stable.count"

  [ -f "$last_hash_file" ] || : >"$last_hash_file"
  [ -f "$stable_count_file" ] || echo 0 >"$stable_count_file"

  json_array_from_args() {
    if [ "$#" -eq 0 ]; then
      echo '[]'
    else
      printf '%s\n' "$@" | jq -R . | jq -s .
    fi
  }

  run_check() {
    local container="$1"
    local dns_probe_name="$2"

    systemd-run --quiet --wait --collect --pipe -M "$container" \
      --setenv=DNS_PROBE_NAME="$dns_probe_name" \
      /bin/sh -lc ${lib.escapeShellArg containerCheck} 2>/dev/null \
        || jq -n "{ error: \"check-failed\" }"
  }

  while true; do
    now="$(date --iso-8601=seconds)"
    mapfile -t expected < <(jq -r '.expectedContainers[]' "$plan")
    interval="$(jq -r '.intervalSeconds' "$plan")"
    dns_probe_name="$(jq -r '.dnsProbeName // "example.com"' "$plan")"

    missing=()
    running=()

    for container in "''${expected[@]}"; do
      state="$(machinectl show "$container" -p State --value 2>/dev/null || true)"
      if [ "$state" = "running" ]; then
        running+=("$container")
      else
        missing+=("$container")
      fi
    done

    if [ "''${#missing[@]}" -ne 0 ]; then
      jq -n \
        --arg updatedAt "$now" \
        --argjson expected "$(jq -c '.expectedContainers' "$plan")" \
        --argjson running "$(json_array_from_args "''${running[@]}")" \
        --argjson missing "$(json_array_from_args "''${missing[@]}")" \
        '{
          updatedAt: $updatedAt,
          ready: false,
          expectedContainers: $expected,
          runningContainers: $running,
          missingContainers: $missing,
          checks: {}
        }' >"$status_json"
      cp "$status_json" "$stable_json"
      sleep "$interval"
      continue
    fi

    tmp_checks="$state_dir/checks.jsonl"
    : >"$tmp_checks"

    for container in "''${expected[@]}"; do
      check_json="$(run_check "$container" "$dns_probe_name")"
      jq -cn --arg container "$container" --argjson result "$check_json" \
        '{ key: $container, value: $result }' >>"$tmp_checks"
    done

    checks_json="$(jq -csf ${checksAggregationFilter} "$tmp_checks")"
    checks_healthy="$(
      jq -e '
        to_entries
        | all(
            (.value.error? == null)
            and ((.value.dnsService != true) or (.value.dnsA == "ok" and .value.dnsAAAA == "ok"))
          )
      ' <<<"$checks_json" >/dev/null && echo true || echo false
    )"

    jq -n \
      --arg updatedAt "$now" \
      --argjson expected "$(jq -c '.expectedContainers' "$plan")" \
      --argjson ready "$checks_healthy" \
      --argjson checks "$checks_json" \
      '{ updatedAt: $updatedAt, ready: $ready, expectedContainers: $expected, checks: $checks }' \
      >"$status_json"

    current_hash="$(jq -c 'del(.updatedAt)' "$status_json" | sha256sum | sed 's/ .*//')"
    previous_hash="$(cat "$last_hash_file" || true)"

    if [ "$current_hash" = "$previous_hash" ] && [ -n "$current_hash" ]; then
      stable_count="$(cat "$stable_count_file")"
      stable_count=$((stable_count + 1))
    else
      stable_count=1
    fi

    echo "$current_hash" >"$last_hash_file"
    echo "$stable_count" >"$stable_count_file"

    if [ "$stable_count" -ge 3 ]; then
      cp "$status_json" "$stable_json"
    fi

    sleep "$interval"
  done
''
