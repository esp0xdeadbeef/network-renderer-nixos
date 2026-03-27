{ lib, pkgs, containerName, wanConfig ? { }, ... }:

let
  ifName = "${containerName}-wan";

  cfg = wanConfig;

  pppoe =
    if cfg ? pppoe && builtins.isAttrs cfg.pppoe then
      cfg.pppoe
    else
      { enable = false; };

  pppoeEnabled =
    if pppoe ? enable then
      pppoe.enable
    else
      false;

  usernameSecret =
    if pppoeEnabled then
      if pppoe ? usernameSecret && builtins.isString pppoe.usernameSecret then
        pppoe.usernameSecret
      else
        throw "pppoe.usernameSecret must be defined"
    else
      null;

  passwordSecret =
    if pppoeEnabled then
      if pppoe ? passwordSecret && builtins.isString pppoe.passwordSecret then
        pppoe.passwordSecret
      else
        throw "pppoe.passwordSecret must be defined"
    else
      null;

  mtu =
    if pppoeEnabled then
      if pppoe ? mtu then
        pppoe.mtu
      else
        throw "pppoe.mtu must be defined"
    else
      null;

  mru =
    if pppoeEnabled then
      if pppoe ? mru then
        pppoe.mru
      else
        throw "pppoe.mru must be defined"
    else
      null;

  ipv6 =
    if cfg ? ipv6 && builtins.isAttrs cfg.ipv6 then
      cfg.ipv6
    else if pppoe ? ipv6 && builtins.isAttrs pppoe.ipv6 then
      pppoe.ipv6
    else
      { };

  ipv6Enabled =
    if ipv6 ? enable then
      ipv6.enable
    else
      false;

  ipv6AcceptRA =
    if ipv6 ? acceptRA then
      ipv6.acceptRA
    else
      ipv6Enabled && !pppoeEnabled;

  dhcpv6OnWan =
    if ipv6 ? dhcp then
      ipv6.dhcp
    else
      false;

  dhcpv6PD =
    if ipv6 ? dhcpv6PD then
      ipv6.dhcpv6PD
    else
      false;

  dhcpMode =
    if pppoeEnabled then
      "no"
    else if ipv6Enabled && dhcpv6OnWan then
      "yes"
    else
      "ipv4";

  linkLocalMode =
    if ipv6Enabled || pppoeEnabled then
      "yes"
    else
      "ipv4";

  dhcpv6PDIfName =
    if pppoeEnabled then
      "ppp0"
    else
      ifName;

  pppoePeerIpv6Lines =
    lib.optionalString ipv6Enabled ''
      +ipv6
      ipv6cp-accept-local
      ipv6cp-accept-remote
    '';
in
{
  systemd.network.networks =
    {
      "10-${ifName}" = {
        matchConfig.Name = ifName;

        networkConfig = {
          IPv4Forwarding = true;
          IPv6Forwarding = ipv6Enabled;
          ConfigureWithoutCarrier = true;
          DHCP = dhcpMode;
          IPv6AcceptRA = ipv6AcceptRA;
          LinkLocalAddressing = linkLocalMode;
        };

        dhcpV4Config = lib.optionalAttrs (!pppoeEnabled) {
          UseGateway = true;
          UseRoutes = false;
          RoutesToDNS = false;
          RoutesToNTP = false;
          RouteMetric = 1024;
        };
      };
    }
    // lib.optionalAttrs pppoeEnabled {
      "11-ppp0" = {
        matchConfig.Name = "ppp0";

        networkConfig = {
          ConfigureWithoutCarrier = true;
          IPv6AcceptRA = false;
          IPv4Forwarding = true;
          IPv6Forwarding = ipv6Enabled;
          DHCP = "no";
          LinkLocalAddressing =
            if ipv6Enabled then
              "ipv6"
            else
              "no";
        };
      };
    };

  systemd.services = lib.mkMerge [
    (lib.optionalAttrs pppoeEnabled {
      pppoe-wan = {
        description = "PPPoE WAN";
        wantedBy = [ "multi-user.target" ];
        after = [ "systemd-networkd.service" ];
        requires = [ "systemd-networkd.service" ];

        path = [
          pkgs.ppp
          pkgs.coreutils
        ];

        serviceConfig = {
          Type = "simple";
          Restart = "always";
          RestartSec = 2;

          ExecStartPre = pkgs.writeShellScript "pppoe-setup" ''
            set -euo pipefail
            umask 077

            mkdir -p /run/ppp/peers

            USERNAME="$(cat /run/secrets/${usernameSecret})"
            PASSWORD="$(cat /run/secrets/${passwordSecret})"

            if [ -z "$USERNAME" ] || [ -z "$PASSWORD" ]; then
              echo "ERROR: missing PPPoE credentials" >&2
              exit 1
            fi

            cat > /run/ppp/pap-secrets <<EOF
            "$USERNAME" * "$PASSWORD" *
            EOF
            chmod 600 /run/ppp/pap-secrets

            cat > /run/ppp/peers/pppoe-wan <<EOF
            plugin pppoe.so
            nic-${ifName}

            user "$USERNAME"
            password "$PASSWORD"

            noauth
            refuse-chap
            refuse-mschap
            refuse-mschap-v2
            refuse-eap

            defaultroute
            persist
            ${pppoePeerIpv6Lines}
            mtu ${toString mtu}
            mru ${toString mru}
            EOF
          '';

          ExecStart = ''
            ${pkgs.ppp}/bin/pppd \
              file /run/ppp/peers/pppoe-wan \
              nodetach \
              debug
          '';
        };
      };
    })

    (lib.optionalAttrs dhcpv6PD {
      dhcpcd-ipv6 = {
        description = "DHCPv6 Prefix Delegation client";
        wantedBy = [ "multi-user.target" ];
        after =
          if pppoeEnabled then
            [ "pppoe-wan.service" ]
          else
            [ "systemd-networkd.service" ];
        wants =
          if pppoeEnabled then
            [ "pppoe-wan.service" ]
          else
            [ "systemd-networkd.service" ];

        serviceConfig = {
          ExecStart = "${pkgs.dhcpcd}/bin/dhcpcd -6 -d -B -f /etc/dhcpcd.conf ${dhcpv6PDIfName}";
          Restart = "always";
          RestartSec = 2;
        };
      };
    })
  ];

  environment.etc = lib.optionalAttrs dhcpv6PD {
    "dhcpcd.conf" = {
      mode = "0644";
      text = ''
        duid
        persistent

        nohook resolv.conf
        noipv6rs
        noipv4
        ipv6only

        interface ${dhcpv6PDIfName}
          iaid 1
          ia_pd 1
      '';
    };
  };
}
