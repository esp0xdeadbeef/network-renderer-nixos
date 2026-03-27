# /home/deadbeef/github/nixos/nixos/virtual-machine/nixos-shell-vm/s-router-access/container-router-access/kea-services.nix
# FILE: container-router-access/kea-services.nix
{
  config,
  pkgs,
  lib,
  vlanId,
  outPath,
  ...
}:

let
  lanIf = "lan-${toString vlanId}";
  lanName = "lan${toString vlanId}";
  cfgFile = "/run/etc/kea/${lanName}.json";

  waitIface = pkgs.writeShellScript "wait-iface-ready-${lanName}" ''
    set -euo pipefail
    IF="$1"
    echo "[kea] waiting for interface $IF"

    for i in $(seq 1 80); do
      if ${pkgs.iproute2}/bin/ip link show "$IF" >/dev/null 2>&1; then
        if ${pkgs.iproute2}/bin/ip link show "$IF" | ${pkgs.gnugrep}/bin/grep -q "UP"; then
          echo "[kea] interface $IF is UP"
          exit 0
        fi
      fi
      sleep 0.25
    done

    echo "[kea] ERROR: interface $IF never became UP" >&2
    ${pkgs.iproute2}/bin/ip link show "$IF" || true
    exit 1
  '';

  postCheck = pkgs.writeShellScript "kea-post-check-${lanName}" ''
    set -euo pipefail
    IF="$1"

    echo "[kea] post-check: verifying DHCP socket on $IF"
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
      echo "[kea] ERROR: Kea is not listening on UDP/67 for $IF" >&2
      echo "[kea] interface IPs: $IPS" >&2
      ${pkgs.iproute2}/bin/ss -u -l -n >&2
      exit 1
    fi

    echo "[kea] OK: Kea bound to UDP/67 on $IF"
  '';
in
{
  systemd.services."kea-dhcp4-${lanName}" = {
    description = "Kea DHCPv4 on ${lanIf}";
    wantedBy = [ "multi-user.target" ];
    after = [
      "systemd-networkd.service"
      "gen-kea-${lanName}.service"
    ];
    requires = [
      "systemd-networkd.service"
      "gen-kea-${lanName}.service"
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
        "${waitIface} ${lib.escapeShellArg lanIf}"
      ];

      ExecStart = "${pkgs.kea}/bin/kea-dhcp4 -d -c ${cfgFile}";

      ExecStartPost = [
        "${postCheck} ${lib.escapeShellArg lanIf}"
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
