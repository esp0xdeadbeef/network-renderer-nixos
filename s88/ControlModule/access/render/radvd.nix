{
  lib,
  pkgs,
  scope,
}:

let
  cfgFile = "/run/radvd-${scope.fileStem}.conf";

  waitIface = pkgs.writeShellScript "wait-iface-ready-radvd-${scope.fileStem}" ''
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

  genConfig = pkgs.writeShellScript "gen-radvd-${scope.fileStem}" ''
    set -euo pipefail
    mkdir -p /run

    cat > ${lib.escapeShellArg cfgFile} <<'EOF'
    interface ${scope.interfaceName} {
      AdvSendAdvert on;
      MinRtrAdvInterval 10;
      MaxRtrAdvInterval 30;
      AdvManagedFlag off;
      AdvOtherConfigFlag off;
    ${lib.optionalString (scope.rdnss != [ ]) ''
      RDNSS ${builtins.concatStringsSep " " scope.rdnss} {
        AdvRDNSSLifetime 600;
      };
    ''}
    ${lib.optionalString (scope.domain != "") ''
      DNSSL ${scope.domain} {
        AdvDNSSLLifetime 600;
      };
    ''}
    ${lib.concatMapStrings (prefix: ''
      prefix ${prefix} {
        AdvOnLink on;
        AdvAutonomous on;
      };
    '') scope.prefixes}
    };
    EOF
  '';
in
{
  environment.systemPackages = [
    pkgs.radvd
    pkgs.iproute2
    pkgs.gnugrep
    pkgs.coreutils
  ];

  systemd.services."radvd-generate-${scope.fileStem}" = {
    wantedBy = [ "multi-user.target" ];
    after = [ "systemd-networkd.service" ];
    requires = [ "systemd-networkd.service" ];
    serviceConfig = {
      Type = "oneshot";
      ExecStart = genConfig;
      RemainAfterExit = true;
    };
  };

  systemd.services."radvd-${scope.fileStem}" = {
    description = "Router advertisements on ${scope.interfaceName}";
    wantedBy = [ "multi-user.target" ];
    after = [
      "systemd-networkd.service"
      "radvd-generate-${scope.fileStem}.service"
    ];
    requires = [
      "systemd-networkd.service"
      "radvd-generate-${scope.fileStem}.service"
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

      ExecStart = "${pkgs.radvd}/bin/radvd -n -C ${cfgFile}";
      Restart = "always";
      RestartSec = "2s";

      CapabilityBoundingSet = [
        "CAP_NET_ADMIN"
        "CAP_NET_RAW"
      ];

      AmbientCapabilities = [
        "CAP_NET_ADMIN"
        "CAP_NET_RAW"
      ];
    };
  };
}
