{
  lib,
  pkgs,
  coreLaneInterfaces,
  renderedInterfaceNames,
}:

let
  lanes = map (name: renderedInterfaceNames.${name}) coreLaneInterfaces;

  sanitize = value: lib.replaceStrings [ "/" ":" "." "@" ] [ "-" "-" "-" "-" ] value;

  serviceFor = lane: {
    name = "s88-lane-health-${sanitize lane}";
    value = {
      description = "Gate core lane ${lane} when its egress fails";
      wantedBy = [ "multi-user.target" ];
      after = [ "network-pre.target" ];
      path = [
        pkgs.coreutils
        pkgs.iproute2
        pkgs.iputils
      ];
      serviceConfig = {
        Type = "oneshot";
      };
      script = ''
        set -euo pipefail
        lane=${lib.escapeShellArg lane}
        marker=/run/s88-lane-health-${sanitize lane}.was-up
        if ! ip link show "$lane" >/dev/null 2>&1; then
          exit 0
        fi




        ip link set "$lane" up 2>/dev/null || true




        addr="$(ip -4 -o addr show "$lane" 2>/dev/null | tr -s ' ' | cut -d' ' -f4 | head -1)"
        peer=""
        if [ -n "$addr" ]; then
          ipv4="''${addr%/*}"
          prefix="''${addr#*/}"
          if [ "$prefix" = "31" ]; then
            peer="''${ipv4%.*}.$(( ''${ipv4##*.} ^ 1 ))"
          fi
        fi
        if [ -n "$peer" ]; then
          ip route replace "$peer/32" dev "$lane" 2>/dev/null || true
        fi
        sleep 1
        if [ -n "$peer" ] && ${pkgs.iputils}/bin/ping -c1 -W2 -I "$lane" "$peer" >/dev/null 2>&1; then
          touch "$marker"
          exit 0
        fi



        if [ -e "$marker" ]; then
          ip link set "$lane" down 2>/dev/null || true
          rm -f "$marker"
          echo "[lane-health] $lane peer probe failed after it was up; gated the lane" >&2
        else
          echo "[lane-health] $lane peer not reachable yet; leaving lane up" >&2
        fi
      '';
    };
  };
in
{
  config = lib.mkIf (lanes != [ ]) {
    systemd.services = builtins.listToAttrs (map serviceFor lanes);
    systemd.timers = lib.listToAttrs (
      map (lane: {
        name = "s88-lane-health-${sanitize lane}";
        value = {
          description = "Periodic egress probe for core lane ${lane}";
          wantedBy = [ "timers.target" ];
          timerConfig = {
            OnBootSec = "20s";
            OnUnitActiveSec = "15s";
            AccuracySec = "2s";
            Unit = "s88-lane-health-${sanitize lane}.service";
          };
        };
      }) lanes
    );
  };
}
