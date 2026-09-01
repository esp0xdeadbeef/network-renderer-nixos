{
  lib,
  pkgs,
  renderedModel,
  uplinks ? { },
  wanUplinkName ? null,
}:

let
  interfaces =
    if builtins.isAttrs (renderedModel.interfaces or null) then renderedModel.interfaces else { };
  attrsOrEmpty = value: if builtins.isAttrs value then value else { };

  ifaceNameFor =
    logicalName:
    let
      iface = interfaces.${logicalName} or { };
    in
    if
      builtins.isString (iface.containerInterfaceName or null) && iface.containerInterfaceName != ""
    then
      iface.containerInterfaceName
    else if builtins.isString (iface.hostInterfaceName or null) && iface.hostInterfaceName != "" then
      iface.hostInterfaceName
    else
      logicalName;

  assignedUplinkFor =
    logicalName:
    let
      iface = attrsOrEmpty (interfaces.${logicalName} or null);
    in
    if
      builtins.isString (iface.assignedUplinkName or null)
      && builtins.hasAttr iface.assignedUplinkName uplinks
    then
      uplinks.${iface.assignedUplinkName}
    else if
      (iface.sourceKind or null) == "wan"
      && builtins.isString wanUplinkName
      && builtins.hasAttr wanUplinkName uplinks
    then
      uplinks.${wanUplinkName}
    else
      { };

  dhcpClientFor =
    logicalName:
    let
      uplink = assignedUplinkFor logicalName;
      ipv4 = attrsOrEmpty (uplink.ipv4 or null);
    in
    ipv4.dhcpClient or "systemd";

  dhcpOptionsFor =
    logicalName:
    let
      uplink = assignedUplinkFor logicalName;
      ipv4 = attrsOrEmpty (uplink.ipv4 or null);
    in
    if builtins.isList (ipv4.dhcpOptions or null) then ipv4.dhcpOptions else [ ];

  nonSystemdWan = builtins.filter (
    logicalName:
    (interfaces.${logicalName}.sourceKind or null) == "wan" && (dhcpClientFor logicalName) != "systemd"
  ) (builtins.attrNames interfaces);

  sanitizeName = value: builtins.replaceStrings [ "/" ":" "." "@" ] [ "-" "-" "-" "-" ] value;

  serviceFor =
    logicalName:
    let
      ifaceName = ifaceNameFor logicalName;
      client = dhcpClientFor logicalName;
      unit = "s88-udhcpc-${sanitizeName logicalName}";
      udhcpcScript = pkgs.writeShellScript "s88-udhcpc-script" ''
        set -euo pipefail
        case "$1" in
          bound|renew)
            if [ -n "''${ip:-}" ]; then
              ip addr add "''${ip}/''${mask:-24}" dev "$interface" 2>/dev/null || true
            fi
            if [ -n "''${dns:-}" ]; then
              : > /run/wan-dns.conf
              for d in $dns; do
                echo "nameserver $d" >> /run/wan-dns.conf
              done
            fi
            ;;
          deconfig)
            : > /run/wan-dns.conf
            ;;
        esac
        exit 0
      '';
      exec =
        if client == "udhcpc" then
          "${pkgs.busybox}/bin/udhcpc -C -R ${
            lib.concatMapStringsSep " " (opt: "-O ${opt}") (dhcpOptionsFor logicalName)
          } -s ${udhcpcScript} -i ${lib.escapeShellArg ifaceName} -f"
        else if client == "dhcpcd" then
          "${pkgs.dhcpcd}/bin/dhcpcd -4 --noclientid ${lib.escapeShellArg ifaceName}"
        else
          throw "invalid ipv4.dhcpClient '${client}' for ${logicalName}; expected udhcpc or dhcpcd";
    in
    {
      name = unit;
      value = {
        description = "DHCPv4 (${client}, no client-id) on ${ifaceName}";
        wantedBy = [ "multi-user.target" ];
        after = [ "network-pre.target" ];
        serviceConfig = {
          Type = "simple";
          Restart = "always";
          RestartSec = 3;
          ExecStart = exec;
        };
      };
    };
in
{
  config = lib.mkIf (nonSystemdWan != [ ]) {
    systemd.services = builtins.listToAttrs (map serviceFor nonSystemdWan);
  };
}
