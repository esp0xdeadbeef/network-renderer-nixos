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

  nonSystemdWan = builtins.filter (
    logicalName:
    (interfaces.${logicalName}.sourceKind or null) == "wan" && (dhcpClientFor logicalName) != "systemd"
  ) (builtins.attrNames interfaces);

  sanitizeName = value: builtins.replaceStrings [ "/" ":" "." "@" ] [ "-" "-" "-" "-" ] value;

  udhcpcScript = pkgs.writeShellScript "s88-udhcpc-script" ''
    set -e
    action="$1"
    case "$action" in
      config)
        ip -4 addr flush dev "$interface" 2>/dev/null || true
        ip -4 addr add "$ip/$subnet" dev "$interface"
        ip link set "$interface" up
        if [ -n "$router" ]; then
          ip -4 route replace default via "$router" dev "$interface" onlink
        fi
        ;;
      deconfig)
        ip -4 route flush dev "$interface" 2>/dev/null || true
        ip -4 addr flush dev "$interface" 2>/dev/null || true
        ip link set "$interface" up
        ;;
      leasefail | nak)
        echo "udhcpc: $action: ${"message:-"}" >&2
        ;;
    esac
    exit 0
  '';

  serviceFor =
    logicalName:
    let
      ifaceName = ifaceNameFor logicalName;
      client = dhcpClientFor logicalName;
      unit = "s88-udhcpc-${sanitizeName logicalName}";
      exec =
        if client == "udhcpc" then
          "${pkgs.busybox}/bin/udhcpc -C -R -i ${lib.escapeShellArg ifaceName} -f -s ${udhcpcScript}"
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
        path = [
          pkgs.iproute2
          pkgs.coreutils
        ];
      };
    };
in
{
  config = lib.mkIf (nonSystemdWan != [ ]) {
    systemd.services = builtins.listToAttrs (map serviceFor nonSystemdWan);
  };
}
