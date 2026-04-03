{
  lib,
  pkgs,
  scope,
}:

let
  cfgFile = "/run/etc/kea/${scope.fileStem}.json";

  configJson = builtins.toJSON {
    Dhcp4 = {
      "interfaces-config" = {
        interfaces = [ scope.interfaceName ];
      };

      "lease-database" = {
        type = "memfile";
        persist = true;
        name = "/var/lib/kea/${scope.fileStem}.leases";
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
    mkdir -p /run/etc/kea /var/lib/kea

    cat > ${lib.escapeShellArg cfgFile} <<'EOF'
    ${configJson}
    EOF
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
    ];
    requires = [
      "systemd-networkd.service"
      "gen-kea-${scope.fileStem}.service"
    ];

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
}
