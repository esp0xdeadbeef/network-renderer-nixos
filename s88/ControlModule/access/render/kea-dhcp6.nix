{ lib
, pkgs
, scope
,
}:

let
  cfgFile = "/run/etc/kea/${scope.fileStem}-dhcp6.json";
  lease = (import ./lease-state.nix {
    service = "DHCPv6";
    fileStem = scope.fileStem;
    suffix = "-dhcp6";
  }) (scope.leaseState or null);
  reservations =
    map
      (reservation:
        (
          if builtins.isString (reservation.duid or null) && reservation.duid != "" then
            { duid = reservation.duid; }
          else
            { "hw-address" = reservation.mac; }
        )
        // {
          "ip-addresses" = [ reservation.address ];
        }
        // lib.optionalAttrs (builtins.isString (reservation.hostname or null) && reservation.hostname != "") {
          hostname = reservation.hostname;
        })
      (scope.reservations or [ ]);

  configJson = builtins.toJSON {
    Dhcp6 = {
      "interfaces-config" = {
        interfaces = [ scope.interfaceName ];
      };

      "lease-database" = {
        type = "memfile";
        persist = lease.persist;
        name = lease.path;
      };

      subnet6 = [
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
              name = "dns-servers";
              data = builtins.concatStringsSep ", " scope.dnsServers;
            }
            {
              name = "domain-search";
              data = scope.domain;
            }
          ];
          inherit reservations;
        }
      ];
    };
  };

  genConfig = pkgs.writeShellScript "gen-kea-dhcp6-${scope.fileStem}" ''
    set -euo pipefail
    mkdir -p /run/etc/kea ${lib.escapeShellArg lease.directory}

    cat > ${lib.escapeShellArg cfgFile} <<'EOF'
    ${configJson}
    EOF
  '';

  waitIface = pkgs.writeShellScript "wait-iface-ready-kea-dhcp6-${scope.fileStem}" ''
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
in
{
  environment.systemPackages = [
    pkgs.kea
    pkgs.iproute2
    pkgs.gnugrep
    pkgs.coreutils
  ];

  systemd.services."gen-kea-dhcp6-${scope.fileStem}" = {
    wantedBy = [ "multi-user.target" ];
    before = [ "kea-dhcp6-${scope.fileStem}.service" ];
    serviceConfig = {
      Type = "oneshot";
      ExecStart = genConfig;
      RemainAfterExit = true;
    };
  };

  systemd.services."kea-dhcp6-${scope.fileStem}" = {
    description = "Kea DHCPv6 on ${scope.interfaceName}";
    wantedBy = [ "multi-user.target" ];
    after = [
      "systemd-networkd.service"
      "gen-kea-dhcp6-${scope.fileStem}.service"
    ];
    requires = [
      "systemd-networkd.service"
      "gen-kea-dhcp6-${scope.fileStem}.service"
    ];

    path = [
      pkgs.coreutils
      pkgs.iproute2
      pkgs.gnugrep
    ];

    serviceConfig = {
      Type = "simple";

      ExecStartPre = [
        "${waitIface} ${lib.escapeShellArg scope.interfaceName}"
      ];

      ExecStart = "${pkgs.kea}/bin/kea-dhcp6 -d -c ${cfgFile}";

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
}
