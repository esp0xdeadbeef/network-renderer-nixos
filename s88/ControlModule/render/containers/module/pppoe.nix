{
  lib,
  pkgs,
  renderedModel,
}:

let
  services =
    if builtins.isAttrs (renderedModel.services or null) then renderedModel.services else { };
  pppoe = if builtins.isAttrs (services.pppoe or null) then services.pppoe else { };
  unitName =
    if builtins.isString (renderedModel.unitName or null) then renderedModel.unitName else "";

  ifaceNameFor =
    logicalName:
    let
      iface = (renderedModel.interfaces or { }).${logicalName} or { };
    in
    if
      builtins.isString (iface.containerInterfaceName or null) && iface.containerInterfaceName != ""
    then
      iface.containerInterfaceName
    else if builtins.isString (iface.hostInterfaceName or null) && iface.hostInterfaceName != "" then
      iface.hostInterfaceName
    else
      logicalName;

  lowerInterfaceForPppoe =
    role: serviceInterface:
    let
      interfaces =
        if builtins.isAttrs (renderedModel.interfaces or null) then renderedModel.interfaces else { };
      runtimeTarget =
        if builtins.isAttrs (renderedModel.runtimeTarget or null) then renderedModel.runtimeTarget else { };
      effective =
        if builtins.isAttrs (runtimeTarget.effectiveRuntimeRealization or null) then
          runtimeTarget.effectiveRuntimeRealization
        else
          { };
      effectiveInterfaces =
        if builtins.isAttrs (effective.interfaces or null) then effective.interfaces else { };
      pppoeSessions = builtins.filter (
        iface:
        builtins.isAttrs (iface.pppoe or null)
        && (iface.pppoe.serviceInterface or null) == serviceInterface
        && (iface.pppoe.role or null) == role
      ) (builtins.attrValues effectiveInterfaces);
      preferredSourceKind = if role == "client" then "wan" else "p2p";
      candidates = builtins.filter (
        name:
        let
          iface = effectiveInterfaces.${name};
        in
        (iface.sourceKind or null) == preferredSourceKind
      ) (builtins.attrNames effectiveInterfaces);
    in
    if builtins.hasAttr serviceInterface interfaces then
      serviceInterface
    else if pppoeSessions != [ ] && builtins.length candidates == 1 then
      builtins.head candidates
    else
      serviceInterface;

  credentialReadCommand =
    credentials: field:
    let
      fileField = "${field}File";
      fileValue = credentials.${fileField} or null;
    in
    if builtins.isString fileValue && fileValue != "" then
      "${pkgs.coreutils}/bin/test -s ${lib.escapeShellArg fileValue} && ${pkgs.coreutils}/bin/cat ${lib.escapeShellArg fileValue} || { echo NixOS PPPoE renderer: credential file is empty >&2; exit 1; }"
    else
      throw "NixOS PPPoE renderer requires non-empty credentials.usernameFile and credentials.passwordFile paths";

  sanitizeName = value: builtins.replaceStrings [ "/" ":" "." "@" ] [ "-" "-" "-" "-" ] value;

  clientConfig = if builtins.isAttrs (pppoe.client or null) then pppoe.client else null;
  serverConfig = if builtins.isAttrs (pppoe.server or null) then pppoe.server else null;
  validation = import ./pppoe/validation.nix { inherit renderedModel; };

  clientPeer =
    if clientConfig == null then
      null
    else
      let
        logicalIf = clientConfig.interface;
        lowerLogicalIf = lowerInterfaceForPppoe "client" logicalIf;
        interfaceName = ifaceNameFor lowerLogicalIf;
        peerName = "s88-pppoe-client-${sanitizeName logicalIf}";
        systemdUnitName = "pppd-${peerName}";
        starterServiceName = "s88-start-${peerName}";
        starterTimerName = "${starterServiceName}";
        runtimeOptions = "/run/pppd/${peerName}.options";
        credentials = clientConfig.credentials or { };
        pppName =
          clientConfig.runtimeInterface
            or (throw "FS-310-HDS-030-SDS-010-SMS-111: clientConfig.runtimeInterface required by CPM provider contract, cannot default to 'ppp0'");
        mtu = toString (clientConfig.mtu or 1492);
        defaultRouteLines =
          if clientConfig.defaultRoute or true then
            ''
              defaultroute
              replacedefaultroute
            ''
          else
            "";
        usePeerDns = clientConfig.usePeerDns or true;
        peerDns = import ./pppoe/client-peer-dns.nix {
          inherit
            lib
            pkgs
            peerName
            usePeerDns
            ;
          scriptSuffix = sanitizeName logicalIf;
        };
        ipUp = pkgs.writeShellScript "s88-pppoe-ip-up-${sanitizeName logicalIf}" ''
          set -eu
          if [ "$1" != ${lib.escapeShellArg pppName} ]; then
            ${pkgs.iproute2}/bin/ip link set "$1" name ${lib.escapeShellArg pppName} || true
          fi
          ${peerDns.ipUpBlock}
        '';
      in
      {
        inherit peerName systemdUnitName starterServiceName starterTimerName;
        peer = {
          enable = true;
          autostart = false;
          config = ''
            file ${runtimeOptions}
          '';
        };
        service = {
          path = [
            pkgs.coreutils
            pkgs.iproute2
            pkgs.ppp
          ];
          serviceConfig = {
            Restart = lib.mkDefault "always";
            RestartSec = lib.mkDefault 5;
          };
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
            ifname ${pppName}
            ${defaultRouteLines}
            ${peerDns.options}
            persist
            maxfail 0
            +ipv6
            ipv6cp-accept-local
            ipv6cp-accept-remote
            mtu ${mtu}
            mru ${mtu}
            ip-up-script ${ipUp}
            ${peerDns.ipDownOption}
            EOF
          '';
        };
        starterService = {
          description = "Start S88 PPPoE client ${peerName}";
          wantedBy = [ "multi-user.target" ];
          after = [ "network-online.target" "s88-rename-interfaces.service" ];
          wants = [ "network-online.target" ];
          serviceConfig = {
            Type = "oneshot";
            ExecStart = "${pkgs.systemd}/bin/systemctl --no-block start ${systemdUnitName}.service";
          };
        };
        starterTimer = {
          description = "Delay S88 PPPoE client ${peerName} until the container host has attached extra veths";
          wantedBy = [ "timers.target" ];
          timerConfig = {
            OnBootSec = "10s";
            Unit = "${starterServiceName}.service";
          };
        };
      };

  serverUnit =
    if serverConfig == null then
      { }
    else
      let
        logicalIf = serverConfig.interface;
        lowerLogicalIf = lowerInterfaceForPppoe "server" logicalIf;
        interfaceName = ifaceNameFor lowerLogicalIf;
        credentials = serverConfig.credentials or { };
        providerAddress = serverConfig.providerAddress;
        customerAddress = serverConfig.customerAddress;
        mtu = toString (
          serverConfig.mtu
            or (throw "FS-310-HDS-030-SDS-010-SMS-111: serverConfig.mtu required by CPM provider contract, cannot default to 1492")
        );
        maxSessions = toString (
          serverConfig.maxSessions
            or (throw "FS-310-HDS-030-SDS-010-SMS-111: serverConfig.maxSessions required by CPM provider contract, cannot default to 32")
        );
        runtimeDirectory = "s88-pppoe-server";
        pidFile = "/run/${runtimeDirectory}/pppoe-server.pid";
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
            Type = "forking";
            RuntimeDirectory = runtimeDirectory;
            PIDFile = pidFile;
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
              -N ${maxSessions} \
              -X ${lib.escapeShellArg pidFile}
          '';
        };
      };

  clientServices =
    if clientPeer == null then
      { }
    else
      {
        ${clientPeer.systemdUnitName} = clientPeer.service;
        ${clientPeer.starterServiceName} = clientPeer.starterService;
      };
  clientTimers =
    if clientPeer == null then
      { }
    else
      {
        ${clientPeer.starterTimerName} = clientPeer.starterTimer;
      };
in
{
  config = lib.mkIf (clientConfig != null || serverConfig != null) {
    assertions = [
      {
        assertion = validation.clientAssertion clientConfig;
        message = "NixOS PPPoE client service requires services.pppoe.client.interface to name a rendered interface, non-empty credentials.usernameFile and credentials.passwordFile paths with no inline username/password values, and supported implementation 'rp-pppoe'";
      }
      {
        assertion = validation.serverAssertion serverConfig;
        message = "NixOS PPPoE server service requires services.pppoe.server.interface to name a rendered interface, providerAddress, customerAddress, non-empty credentials.usernameFile and credentials.passwordFile paths with no inline username/password values, and supported implementation 'rp-pppoe'";
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
    systemd.timers = clientTimers;
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
