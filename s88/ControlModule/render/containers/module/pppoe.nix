{ lib, pkgs, renderedModel }:

let
  services = if builtins.isAttrs (renderedModel.services or null) then renderedModel.services else { };
  pppoe = if builtins.isAttrs (services.pppoe or null) then services.pppoe else { };
  unitName = if builtins.isString (renderedModel.unitName or null) then renderedModel.unitName else "";

  ifaceNameFor =
    logicalName:
    let
      iface = (renderedModel.interfaces or { }).${logicalName} or { };
    in
    if builtins.isString (iface.containerInterfaceName or null) && iface.containerInterfaceName != "" then
      iface.containerInterfaceName
    else if builtins.isString (iface.hostInterfaceName or null) && iface.hostInterfaceName != "" then
      iface.hostInterfaceName
    else
      logicalName;

  credentialReadCommand =
    credentials: field:
    let
      fileField = "${field}File";
      value = credentials.${field} or null;
      fileValue = credentials.${fileField} or null;
    in
    if builtins.isString fileValue && fileValue != "" then
      "${pkgs.coreutils}/bin/cat ${lib.escapeShellArg fileValue}"
    else if builtins.isString value then
      "${pkgs.coreutils}/bin/printf '%s' ${lib.escapeShellArg value}"
    else
      "false";

  sanitizeName = value: builtins.replaceStrings [ "/" ":" "." "@" ] [ "-" "-" "-" "-" ] value;

  clientConfig = if builtins.isAttrs (pppoe.client or null) then pppoe.client else null;
  serverConfig = if builtins.isAttrs (pppoe.server or null) then pppoe.server else null;

  clientPeer =
    if clientConfig == null then
      null
    else
      let
        logicalIf = clientConfig.interface;
        interfaceName = ifaceNameFor logicalIf;
        peerName = "s88-pppoe-client-${sanitizeName logicalIf}";
        systemdUnitName = "pppd-${peerName}";
        runtimeOptions = "/run/pppd/${peerName}.options";
        credentials = clientConfig.credentials or { };
        pppName = clientConfig.runtimeInterface or "ppp0";
        mtu = toString (clientConfig.mtu or 1492);
        defaultRouteLines =
          if clientConfig.defaultRoute or true then
            ''
              defaultroute
              replacedefaultroute
            ''
          else
            "";
        usePeerDnsLine = if clientConfig.usePeerDns or true then "usepeerdns" else "";
        ipUp = pkgs.writeShellScript "s88-pppoe-ip-up-${sanitizeName logicalIf}" ''
          set -eu
          if [ "$1" != ${lib.escapeShellArg pppName} ]; then
            ${pkgs.iproute2}/bin/ip link set "$1" name ${lib.escapeShellArg pppName} || true
          fi
        '';
      in
      {
        inherit peerName systemdUnitName;
        peer = {
          enable = true;
          autostart = true;
          config = ''
            file ${runtimeOptions}
          '';
        };
        service = {
          after = [ "network-online.target" ];
          wants = [ "network-online.target" ];
          path = [
            pkgs.coreutils
            pkgs.iproute2
            pkgs.ppp
          ];
          preStart = ''
            set -eu
            ${pkgs.coreutils}/bin/mkdir -p /run/pppd
            ${pkgs.iproute2}/bin/ip link set ${lib.escapeShellArg interfaceName} up
            user="$(${credentialReadCommand credentials "username"})"
            pass="$(${credentialReadCommand credentials "password"})"
            ${pkgs.coreutils}/bin/install -m 0600 /dev/null ${runtimeOptions}
            cat > ${runtimeOptions} <<EOF
            plugin pppoe.so
            nic-${interfaceName}
            user "$user"
            password "$pass"
            noauth
            refuse-chap
            refuse-mschap
            refuse-mschap-v2
            refuse-eap
            noipdefault
            ${defaultRouteLines}
            ${usePeerDnsLine}
            persist
            maxfail 0
            +ipv6
            ipv6cp-accept-local
            ipv6cp-accept-remote
            mtu ${mtu}
            mru ${mtu}
            ip-up-script ${ipUp}
            EOF
          '';
        };
      };

  serverUnit =
    if serverConfig == null then
      { }
    else
      let
        logicalIf = serverConfig.interface;
        interfaceName = ifaceNameFor logicalIf;
        credentials = serverConfig.credentials or { };
        providerAddress = serverConfig.providerAddress;
        customerAddress = serverConfig.customerAddress;
        mtu = toString (serverConfig.mtu or 1492);
        maxSessions = toString (serverConfig.maxSessions or 32);
      in
      {
        s88-pppoe-server = {
          description = "S88 PPPoE access service on ${interfaceName}";
          wantedBy = [ "multi-user.target" ];
          after = [ "network-online.target" ];
          wants = [ "network-online.target" ];
          path = [
            pkgs.coreutils
            pkgs.iproute2
            pkgs.ppp
            pkgs.rp-pppoe
          ];
          serviceConfig = {
            Type = "simple";
            Restart = "always";
            RestartSec = 2;
          };
          script = ''
            set -eu
            ${pkgs.iproute2}/bin/ip link set ${lib.escapeShellArg interfaceName} up
            ${pkgs.coreutils}/bin/mkdir -p /etc/ppp
            user="$(${credentialReadCommand credentials "username"})"
            pass="$(${credentialReadCommand credentials "password"})"
            ${pkgs.coreutils}/bin/install -m 0600 /dev/null /etc/ppp/chap-secrets
            ${pkgs.coreutils}/bin/install -m 0600 /dev/null /etc/ppp/pap-secrets
            printf '%s * %s *\n' "$user" "$pass" > /etc/ppp/chap-secrets
            printf '* * %s *\n' "$pass" >> /etc/ppp/chap-secrets
            printf '%s * %s *\n' "$user" "$pass" > /etc/ppp/pap-secrets
            printf '* * %s *\n' "$pass" >> /etc/ppp/pap-secrets
            cat > /etc/ppp/s88-pppoe-server-options <<EOF
            require-pap
            refuse-chap
            refuse-mschap
            refuse-mschap-v2
            refuse-eap
            noauth
            nobsdcomp
            nodeflate
            noccp
            novj
            +ipv6
            ipv6cp-accept-local
            ipv6cp-accept-remote
            lcp-echo-interval 10
            lcp-echo-failure 3
            mtu ${mtu}
            mru ${mtu}
            ms-dns ${providerAddress}
            EOF
            exec ${pkgs.rp-pppoe}/bin/pppoe-server \
              -I ${lib.escapeShellArg interfaceName} \
              -L ${lib.escapeShellArg providerAddress} \
              -R ${lib.escapeShellArg customerAddress} \
              -O /etc/ppp/s88-pppoe-server-options \
              -q ${pkgs.ppp}/bin/pppd \
              -Q ${pkgs.rp-pppoe}/bin/pppoe \
              -N ${maxSessions}
          '';
        };
      };

  clientServices =
    if clientPeer == null then
      { }
    else
      {
        ${clientPeer.systemdUnitName} = clientPeer.service;
      };
in
{
  config = lib.mkIf (clientConfig != null || serverConfig != null) {
    assertions = [
      {
        assertion =
          clientConfig == null
          || (builtins.isString (clientConfig.interface or null) && builtins.isAttrs (clientConfig.credentials or null));
        message = "NixOS PPPoE client service requires services.pppoe.client.interface and credentials";
      }
      {
        assertion =
          serverConfig == null
          || (
            builtins.isString (serverConfig.interface or null)
            && builtins.isString (serverConfig.providerAddress or null)
            && builtins.isString (serverConfig.customerAddress or null)
            && builtins.isAttrs (serverConfig.credentials or null)
          );
        message = "NixOS PPPoE server service requires services.pppoe.server.interface, providerAddress, customerAddress, and credentials";
      }
    ];
    environment.systemPackages = [
      pkgs.ppp
      pkgs.rp-pppoe
    ];
    services.pppd = lib.optionalAttrs (clientPeer != null) {
      enable = true;
      package = pkgs.ppp;
      peers.${clientPeer.peerName} = clientPeer.peer;
    };
    systemd.services = clientServices // serverUnit;
    environment.etc = lib.optionalAttrs (serverConfig != null) {
      "s88/pppoe-tools".text = ''
        pppoe-server=${pkgs.rp-pppoe}/bin/pppoe-server
        pppoe=${pkgs.rp-pppoe}/bin/pppoe
        pppoe-sniff=${pkgs.rp-pppoe}/bin/pppoe-sniff
        pppd=${pkgs.ppp}/bin/pppd
      '';
    };
  };
}
