{ lib
, pkgs
, scope
,
}:

let
  cfgFile = "/run/etc/kea/${scope.fileStem}.json";
  leaseFile = "/var/lib/kea/${scope.fileStem}.leases";
  syncScript = "/run/kea-unbound-sync/${scope.fileStem}.sh";

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
        persist = true;
        name = leaseFile;
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
        }
      ];
    };
  };

  genConfig = pkgs.writeShellScript "gen-kea-${scope.fileStem}" ''
    set -euo pipefail
    mkdir -p /run/etc/kea /run/kea-unbound-sync /var/lib/kea

    cat > ${lib.escapeShellArg cfgFile} <<'EOF'
    ${configJson}
    EOF

    cat > ${lib.escapeShellArg syncScript} <<'EOF'
    #!${pkgs.runtimeShell}
    set -eu

    lease_file=${lib.escapeShellArg leaseFile}
    domain=${lib.escapeShellArg scope.domain}
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
        *) fqdn="$hostname.$domain" ;;
      esac
      case "$fqdn" in
        *.) ;;
        *) fqdn="$fqdn." ;;
      esac

      "$unbound_control" -c /etc/unbound/unbound.conf local_data_remove "$fqdn" >/dev/null 2>&1 || true
      "$unbound_control" -c /etc/unbound/unbound.conf local_data "$fqdn 60 IN A $address" >/dev/null 2>&1 || true
    done
    EOF
    chmod 0755 ${lib.escapeShellArg syncScript}
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
    pkgs.unbound
    pkgs.iproute2
    pkgs.gnugrep
    pkgs.gawk
    pkgs.coreutils
  ];

  systemd.services."gen-kea-${scope.fileStem}" = {
    wantedBy = [ "multi-user.target" ];
    before = [ "kea-dhcp4-${scope.fileStem}.service" ];
    serviceConfig = {
      Type = "oneshot";
      ExecStart = genConfig;
      RemainAfterExit = true;
    };
  };

  systemd.services."kea-dhcp4-${scope.fileStem}" = {
    description = "Kea DHCPv4 on ${scope.interfaceName}";
    wantedBy = [ "multi-user.target" ];
    after = [
      "systemd-networkd.service"
      "gen-kea-${scope.fileStem}.service"
      "unbound.service"
    ];
    requires = [
      "systemd-networkd.service"
      "gen-kea-${scope.fileStem}.service"
    ];
    wants = [ "unbound.service" ];

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
      StateDirectory = "kea";

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

  systemd.services."kea-unbound-sync-${scope.fileStem}" = {
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

  systemd.timers."kea-unbound-sync-${scope.fileStem}" = {
    description = "Best-effort Kea DHCPv4 lease hostname sync for ${scope.interfaceName}";
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnBootSec = "30s";
      OnUnitActiveSec = "60s";
      Unit = "kea-unbound-sync-${scope.fileStem}.service";
    };
  };
}
