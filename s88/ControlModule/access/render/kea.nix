{ lib
, pkgs
, scope
,
}:

let
  cfgFile = "/run/etc/kea/${scope.fileStem}.json";
  lease = (import ./lease-state.nix {
    service = "DHCPv4";
    fileStem = scope.fileStem;
  }) (scope.leaseState or null);
  syncScript = "/run/kea-unbound-sync/${scope.fileStem}.sh";
  requiredLeaseDnsField =
    name: value:
    if builtins.isString value && value != "" then
      value
    else
      throw "NixOS DHCPv4 renderer requires scope.leaseDns.${name} before lease hostnames may be published to DNS";
  leaseDns =
    if (scope.leaseDns or null) == null then
      null
    else if builtins.isAttrs scope.leaseDns then
      let
        rawNamespace = requiredLeaseDnsField "namespace" (scope.leaseDns.namespace or null);
        namespace = if lib.hasSuffix "." rawNamespace then rawNamespace else "${rawNamespace}.";
      in
      {
        ownerScope = requiredLeaseDnsField "ownerScope" (scope.leaseDns.ownerScope or null);
        requesterScope = requiredLeaseDnsField "requesterScope" (scope.leaseDns.requesterScope or null);
        inherit namespace;
      }
    else
      throw "NixOS DHCPv4 renderer requires scope.leaseDns to be an explicit owner/requester namespace contract";
  syncEnabled = leaseDns != null;
  reservationRuntimeSourceFile =
    reservation:
    if
      builtins.isAttrs (reservation.identitySource or null)
      && builtins.isString (reservation.identitySource.sourceFile or null)
      && reservation.identitySource.sourceFile != ""
    then
      reservation.identitySource.sourceFile
    else
      null;
  staticReservationRecords =
    lib.filter (reservation: reservationRuntimeSourceFile reservation == null) (scope.reservations or [ ]);
  runtimeReservationRecords =
    lib.filter (reservation: reservationRuntimeSourceFile reservation != null) (scope.reservations or [ ]);
  runtimeReservationDescriptors =
    map
      (reservation: {
        id =
          if builtins.isString (reservation.id or null) && reservation.id != "" then
            reservation.id
          else
            throw "NixOS DHCPv4 renderer requires runtime-secret reservations to carry a reservation id";
        address = reservation.address;
        sourceFile = reservationRuntimeSourceFile reservation;
      })
      runtimeReservationRecords;
  runtimeReservationsEnabled = runtimeReservationDescriptors != [ ];
  runtimeReservationsJson = builtins.toJSON runtimeReservationDescriptors;
  reservations =
    map
      (reservation:
        {
          "hw-address" = reservation.mac;
          "ip-address" = reservation.address;
        }
        // lib.optionalAttrs (builtins.isString (reservation.hostname or null) && reservation.hostname != "") {
          hostname = reservation.hostname;
        })
      staticReservationRecords;

  # Do not use Kea libdhcp_run_script for this runtime script. Kea restricts
  # that hook to its own packaged script directory, so a /run script makes DHCP
  # fail to start. The timer below keeps hostname sync best-effort.
  configJson = builtins.toJSON {
    Dhcp4 = {
      "interfaces-config" = {
        interfaces = [ scope.interfaceName ];
      };

      "lease-database" = {
        type = "memfile";
        persist = lease.persist;
        name = lease.path;
      };

      subnet4 = [
        {
          id = scope.subnetId;
          subnet = scope.subnet;
          pools = [
            {
              pool = scope.pool;
            }
          ];
          "option-data" = [
            {
              name = "routers";
              data = scope.router;
            }
            {
              name = "domain-name-servers";
              data = builtins.concatStringsSep ", " scope.dnsServers;
            }
            {
              name = "domain-name";
              data = scope.domain;
            }
          ];
          inherit reservations;
        }
      ];
    };
  };

  genConfig = pkgs.writeShellScript "gen-kea-${scope.fileStem}" ''
    set -euo pipefail
    mkdir -p /run/etc/kea ${lib.optionalString syncEnabled "/run/kea-unbound-sync "}${lib.escapeShellArg lease.directory}

    cat > ${lib.escapeShellArg cfgFile} <<'EOF'
    ${configJson}
    EOF

    ${lib.optionalString runtimeReservationsEnabled ''
    runtime_descriptors=${lib.escapeShellArg runtimeReservationsJson}
    runtime_reservations_tmp="$(${pkgs.coreutils}/bin/mktemp ${lib.escapeShellArg "${cfgFile}.runtime-reservations.XXXXXX"})"
    ${pkgs.coreutils}/bin/printf '[]' > "$runtime_reservations_tmp"

    ${pkgs.coreutils}/bin/printf '%s\n' "$runtime_descriptors" | ${pkgs.jq}/bin/jq -c '.[]' |
    while IFS= read -r descriptor; do
      reservation_id="$(${pkgs.coreutils}/bin/printf '%s\n' "$descriptor" | ${pkgs.jq}/bin/jq -r '.id')"
      reservation_address="$(${pkgs.coreutils}/bin/printf '%s\n' "$descriptor" | ${pkgs.jq}/bin/jq -r '.address')"
      reservation_source_file="$(${pkgs.coreutils}/bin/printf '%s\n' "$descriptor" | ${pkgs.jq}/bin/jq -r '.sourceFile')"

      if [ ! -r "$reservation_source_file" ]; then
        echo "[kea] diagnostic.runtime-reservation-secret-record-invalid: runtime reservation source $reservation_source_file missing or unreadable for $reservation_id" >&2
        exit 1
      fi

      if ! ${pkgs.jq}/bin/jq -e 'type' "$reservation_source_file" >/dev/null 2>&1; then
        echo "[kea] diagnostic.runtime-reservation-secret-record-invalid: runtime reservation source $reservation_source_file is not valid JSON for $reservation_id" >&2
        exit 1
      fi

      matched_tmp="$(${pkgs.coreutils}/bin/mktemp ${lib.escapeShellArg "${cfgFile}.runtime-reservation.XXXXXX"})"
      if ! ${pkgs.jq}/bin/jq \
        --arg id "$reservation_id" \
        --arg address "$reservation_address" \
        --arg sourceFile "$reservation_source_file" \
        -e '
          def reservation_objects:
            ..
            | objects
            | select((."hw-address"? | type == "string") and (."ip-address"? | type == "string"));

          def valid_mac:
            test("^([0-9A-Fa-f]{2}:){5}[0-9A-Fa-f]{2}$");

          [
            reservation_objects
            | select(."ip-address" == $address)
          ] as $byAddress
          | (
              if ($byAddress | length) == 1 then
                $byAddress
              else
                [ $byAddress[] | select((.id? == $id) or (.name? == $id)) ]
              end
            ) as $matches
          | if ($matches | length) != 1 then
              error("diagnostic.runtime-reservation-secret-record-invalid: runtime reservation source " + $sourceFile + " must contain exactly one record for " + $id + " at " + $address)
            else
              $matches[0] as $record
              | if (($record."hw-address" | valid_mac) | not) then
                  error("diagnostic.runtime-reservation-secret-record-invalid: runtime reservation source " + $sourceFile + " has invalid hw-address for " + $id)
                else
                  {
                    "hw-address": $record."hw-address",
                    "ip-address": $address
                  }
                  + (
                    if (($record.hostname? // null) | type == "string" and test("^[A-Za-z0-9][A-Za-z0-9._-]*$")) then
                      { hostname: $record.hostname }
                    else
                      {}
                    end
                  )
                end
            end
        ' "$reservation_source_file" > "$matched_tmp"; then
        echo "[kea] diagnostic.runtime-reservation-secret-record-invalid: runtime reservation materialization failed for $reservation_id at $reservation_address from $reservation_source_file" >&2
        exit 1
      fi

      next_runtime_tmp="$(${pkgs.coreutils}/bin/mktemp ${lib.escapeShellArg "${cfgFile}.runtime-reservations-next.XXXXXX"})"
      ${pkgs.jq}/bin/jq --slurpfile entry "$matched_tmp" '. + [$entry[0]]' "$runtime_reservations_tmp" > "$next_runtime_tmp"
      ${pkgs.coreutils}/bin/mv "$next_runtime_tmp" "$runtime_reservations_tmp"
      ${pkgs.coreutils}/bin/rm -f "$matched_tmp"
    done

    tmp="$(${pkgs.coreutils}/bin/mktemp ${lib.escapeShellArg "${cfgFile}.XXXXXX"})"
    ${pkgs.jq}/bin/jq --slurpfile runtime "$runtime_reservations_tmp" '
      .Dhcp4.subnet4[0].reservations = ((.Dhcp4.subnet4[0].reservations // []) + $runtime[0])
      | .Dhcp4.subnet4[0].reservations as $reservations
      | if (($reservations | map(."ip-address") | unique | length) != ($reservations | length)) then
          error("diagnostic.runtime-reservation-secret-record-invalid: duplicate DHCPv4 reservation ip-address after runtime materialization")
        else
          .
        end
      | if (($reservations | map(."hw-address") | unique | length) != ($reservations | length)) then
          error("diagnostic.runtime-reservation-secret-record-invalid: duplicate DHCPv4 reservation hw-address after runtime materialization")
        else
          .
        end
    ' ${lib.escapeShellArg cfgFile} > "$tmp"
    ${pkgs.coreutils}/bin/mv "$tmp" ${lib.escapeShellArg cfgFile}
    ${pkgs.coreutils}/bin/rm -f "$runtime_reservations_tmp"
    ''}

    ${lib.optionalString syncEnabled ''
    cat > ${lib.escapeShellArg syncScript} <<'EOF'
    #!${pkgs.runtimeShell}
    set -eu

    lease_file=${lib.escapeShellArg lease.path}
    namespace=${lib.escapeShellArg leaseDns.namespace}
    owner_scope=${lib.escapeShellArg leaseDns.ownerScope}
    requester_scope=${lib.escapeShellArg leaseDns.requesterScope}
    unbound_control=${pkgs.unbound}/bin/unbound-control

    [ -x "$unbound_control" ] || exit 0
    [ -s "$lease_file" ] || exit 0
    "$unbound_control" -c /etc/unbound/unbound.conf status >/dev/null 2>&1 || exit 0

    awk -F, 'NR > 1 && $10 == "0" && $9 != "" { print $1 "\t" $9 }' "$lease_file" |
    while IFS="$(printf '\t')" read -r address hostname; do
      case "$address:$hostname" in
        *[!A-Za-z0-9:._-]*|:*) continue ;;
      esac
      case "$hostname" in
        *.*) fqdn="$hostname" ;;
        *) fqdn="$hostname.$namespace" ;;
      esac
      case "$fqdn" in
        *.) ;;
        *) fqdn="$fqdn." ;;
      esac
      case "$fqdn" in
        *."$namespace") ;;
        *) continue ;;
      esac
      [ -n "$owner_scope" ] || exit 1
      [ -n "$requester_scope" ] || exit 1

      "$unbound_control" -c /etc/unbound/unbound.conf local_data_remove "$fqdn" >/dev/null 2>&1 || true
      "$unbound_control" -c /etc/unbound/unbound.conf local_data "$fqdn 60 IN A $address" >/dev/null 2>&1 || true
    done
    EOF
    chmod 0755 ${lib.escapeShellArg syncScript}
    ''}
  '';

  waitIface = pkgs.writeShellScript "wait-iface-ready-${scope.fileStem}" ''
    set -euo pipefail
    IF="$1"

    for i in $(seq 1 80); do
      if ${pkgs.iproute2}/bin/ip link show "$IF" >/dev/null 2>&1; then
        if ${pkgs.iproute2}/bin/ip link show "$IF" | ${pkgs.gnugrep}/bin/grep -q "UP"; then
          exit 0
        fi
      fi
      sleep 0.25
    done

    ${pkgs.iproute2}/bin/ip link show "$IF" || true
    exit 1
  '';

  postCheck = pkgs.writeShellScript "kea-post-check-${scope.fileStem}" ''
    set -euo pipefail
    IF="$1"

    sleep 0.5

    IPS="$(${pkgs.iproute2}/bin/ip -4 addr show "$IF" | ${pkgs.gawk}/bin/awk '/inet / {print $2}' | cut -d/ -f1)"
    FOUND=0

    for IP in $IPS; do
      if ${pkgs.iproute2}/bin/ss -u -l -n | ${pkgs.gnugrep}/bin/grep -q "$IP:67"; then
        FOUND=1
        break
      fi
    done

    if [ "$FOUND" -ne 1 ]; then
      ${pkgs.iproute2}/bin/ss -u -l -n >&2
      exit 1
    fi
  '';
in
{
  environment.systemPackages = [
    pkgs.kea
    pkgs.iproute2
    pkgs.gnugrep
    pkgs.gawk
    pkgs.coreutils
  ] ++ lib.optional syncEnabled pkgs.unbound
    ++ lib.optional runtimeReservationsEnabled pkgs.jq;

  systemd.services = {
    "gen-kea-${scope.fileStem}" = {
      wantedBy = [ "multi-user.target" ];
      before = [ "kea-dhcp4-${scope.fileStem}.service" ];
      serviceConfig = {
        Type = "oneshot";
        ExecStart = genConfig;
        RemainAfterExit = true;
      };
    };

    "kea-dhcp4-${scope.fileStem}" = {
      description = "Kea DHCPv4 on ${scope.interfaceName}";
      wantedBy = [ "multi-user.target" ];
      after = [
        "systemd-networkd.service"
        "gen-kea-${scope.fileStem}.service"
      ] ++ lib.optional syncEnabled "unbound.service";
      requires = [
        "systemd-networkd.service"
        "gen-kea-${scope.fileStem}.service"
      ];
      wants = lib.optional syncEnabled "unbound.service";

      path = [
        pkgs.coreutils
        pkgs.iproute2
        pkgs.gnugrep
        pkgs.gawk
      ];

      serviceConfig = {
        Type = "simple";

        ExecStartPre = [
          "${waitIface} ${lib.escapeShellArg scope.interfaceName}"
        ];

        ExecStart = "${pkgs.kea}/bin/kea-dhcp4 -d -c ${cfgFile}";

        ExecStartPost = [
          "${postCheck} ${lib.escapeShellArg scope.interfaceName}"
        ];

        Restart = "always";
        RestartSec = "2s";

        RuntimeDirectory = "kea";

        CapabilityBoundingSet = [
          "CAP_NET_BIND_SERVICE"
          "CAP_NET_ADMIN"
          "CAP_NET_RAW"
        ];

        AmbientCapabilities = [
          "CAP_NET_BIND_SERVICE"
          "CAP_NET_ADMIN"
          "CAP_NET_RAW"
        ];
      };
    };

  } // lib.optionalAttrs syncEnabled {
    "kea-unbound-sync-${scope.fileStem}" = {
      description = "Publish Kea DHCPv4 lease hostnames to Unbound for ${scope.interfaceName}";
      after = [
        "kea-dhcp4-${scope.fileStem}.service"
        "unbound.service"
      ];
      wants = [
        "kea-dhcp4-${scope.fileStem}.service"
        "unbound.service"
      ];
      serviceConfig = {
        Type = "oneshot";
        ExecStart = syncScript;
      };
    };
  };

  systemd.timers = lib.optionalAttrs syncEnabled {
    "kea-unbound-sync-${scope.fileStem}" = {
      description = "Best-effort Kea DHCPv4 lease hostname sync for ${scope.interfaceName}";
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnBootSec = "30s";
        OnUnitActiveSec = "60s";
        Unit = "kea-unbound-sync-${scope.fileStem}.service";
      };
    };
  };
}
