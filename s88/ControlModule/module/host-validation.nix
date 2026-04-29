{
  lib,
  pkgs,
  renderedHostNetwork ? null,
  ...
}:

let
  effectiveRenderedHostNetwork = if renderedHostNetwork != null then renderedHostNetwork else { };

  expectedContainers = lib.sort builtins.lessThan (
    builtins.attrNames (effectiveRenderedHostNetwork.containers or { })
  );

  validationPlan = {
    intervalSeconds = 5;
    expectedContainers = expectedContainers;
    dnsProbeName = "example.com";
  };

  checksAggregationFilter = pkgs.writeText "s88-network-validation-checks.jq" ''
    map({ (.key): .value }) | add
  '';

  validationScript = pkgs.writeShellScript "s88-network-validation-loop" ''
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

    if [ ! -f "$last_hash_file" ]; then
      : >"$last_hash_file"
    fi

    if [ ! -f "$stable_count_file" ]; then
      echo 0 >"$stable_count_file"
    fi

    json_array_from_args() {
      if [ "$#" -eq 0 ]; then
        echo '[]'
      else
        ${pkgs.coreutils}/bin/printf '%s\n' "$@" | ${pkgs.jq}/bin/jq -R . | ${pkgs.jq}/bin/jq -s .
      fi
    }

    run_check() {
      local container="$1"
      local dns_probe_name="$2"

      systemd-run --quiet --wait --collect --pipe -M "$container" \
        --setenv=DNS_PROBE_NAME="$dns_probe_name" /bin/sh -lc '
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
      2>/dev/null || jq -n "{ error: \"check-failed\" }"'
    }

    while true; do
      now="$(${pkgs.coreutils}/bin/date --iso-8601=seconds)"

      mapfile -t expected < <(${pkgs.jq}/bin/jq -r '.expectedContainers[]' "$plan")
      interval="$(${pkgs.jq}/bin/jq -r '.intervalSeconds' "$plan")"
      dns_probe_name="$(${pkgs.jq}/bin/jq -r '.dnsProbeName // "example.com"' "$plan")"

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
        ${pkgs.jq}/bin/jq -n \
          --arg updatedAt "$now" \
          --argjson expected "$(${pkgs.jq}/bin/jq -c '.expectedContainers' "$plan")" \
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
        ${pkgs.coreutils}/bin/cp "$status_json" "$stable_json"
        sleep "$interval"
        continue
      fi

      tmp_checks="$state_dir/checks.jsonl"
      : >"$tmp_checks"

      for container in "''${expected[@]}"; do
        check_json="$(run_check "$container" "$dns_probe_name")"
        ${pkgs.jq}/bin/jq -cn \
          --arg container "$container" \
          --argjson result "$check_json" \
          '{ key: $container, value: $result }' >>"$tmp_checks"
      done

      checks_json="$(${pkgs.jq}/bin/jq -csf ${checksAggregationFilter} "$tmp_checks")"
      checks_healthy="$(
        ${pkgs.jq}/bin/jq -e '
          to_entries
          | all(
              (.value.error? == null)
              and ((.value.dnsService != true) or (.value.dnsA == "ok" and .value.dnsAAAA == "ok"))
            )
        ' <<<"$checks_json" >/dev/null && echo true || echo false
      )"

      ${pkgs.jq}/bin/jq -n \
        --arg updatedAt "$now" \
        --argjson expected "$(${pkgs.jq}/bin/jq -c '.expectedContainers' "$plan")" \
        --argjson ready "$checks_healthy" \
        --argjson checks "$checks_json" \
        '{
          updatedAt: $updatedAt,
          ready: $ready,
          expectedContainers: $expected,
          checks: $checks
        }' >"$status_json"

      current_hash="$(${pkgs.coreutils}/bin/sha256sum "$status_json" | ${pkgs.gnused}/bin/sed 's/ .*//')"
      previous_hash="$(${pkgs.coreutils}/bin/cat "$last_hash_file" || true)"

      if [ "$current_hash" = "$previous_hash" ] && [ -n "$current_hash" ]; then
        stable_count="$(${pkgs.coreutils}/bin/cat "$stable_count_file")"
        stable_count=$((stable_count + 1))
      else
        stable_count=1
      fi

      echo "$current_hash" >"$last_hash_file"
      echo "$stable_count" >"$stable_count_file"

      if [ "$stable_count" -ge 3 ]; then
        ${pkgs.coreutils}/bin/cp "$status_json" "$stable_json"
      fi

      sleep "$interval"
    done
  '';

  validationStatus = pkgs.writeShellScriptBin "s88-network-validation-status" ''
    set -euo pipefail

    target="/run/s88-network-validation/stable.json"
    if [ ! -f "$target" ]; then
      target="/run/s88-network-validation/status.json"
    fi

    if [ ! -f "$target" ]; then
      echo "no validation snapshot yet" >&2
      exit 1
    fi

    exec ${pkgs.jq}/bin/jq . "$target"
  '';
in
{
  environment.etc."s88-network-validation/plan.json".text = builtins.toJSON validationPlan;

  environment.systemPackages = [ validationStatus ];

  systemd.services.s88-network-validation = {
    description = "Continuously validate rendered containers for DNS and IP readiness";
    wantedBy = [ "multi-user.target" ];
    after = [
      "systemd-networkd.service"
      "machines.target"
    ];
    wants = [
      "systemd-networkd.service"
      "machines.target"
    ];
    serviceConfig = {
      Type = "simple";
      Restart = "always";
      RestartSec = 2;
    };
    script = ''
      exec ${validationScript}
    '';
  };
}
