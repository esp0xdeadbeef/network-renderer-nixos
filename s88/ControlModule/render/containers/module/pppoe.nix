{ lib, pkgs, renderedModel }:

let
  site =
    if builtins.isAttrs (renderedModel.site or null) then renderedModel.site else { };

  upstreamEmulation =
    if builtins.isAttrs (site.upstreamEmulation or null) then site.upstreamEmulation else { };

  rowValues = builtins.attrValues upstreamEmulation;

  unitName =
    if builtins.isString (renderedModel.unitName or null) then renderedModel.unitName else "";

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

  clientRows =
    lib.filter
      (
        row:
        let client = ((row.pppoe or { }).client or { });
        in (row.mode or null) == "pppoe"
          && (client.coreNode or null) == unitName
      )
      rowValues;

  clientPeerFor =
    row:
    let
      client = row.pppoe.client;
      server = row.pppoe.server;
      logicalIf = client.coreInterface;
      interfaceName = ifaceNameFor logicalIf;
      peerName = "s88-pppoe-client-${logicalIf}";
      unitName = "pppd-${peerName}";
      runtimeOptions = "/run/pppd/${peerName}.options";
      usernameFile = server.credentials.usernameFile;
      passwordFile = server.credentials.passwordFile;
      pppName = client.runtimeInterface or "ppp0";
      ipUp = pkgs.writeShellScript "s88-pppoe-ip-up-${logicalIf}" ''
        set -eu
        if [ "$1" != ${lib.escapeShellArg pppName} ]; then
          ${pkgs.iproute2}/bin/ip link set "$1" name ${lib.escapeShellArg pppName} || true
        fi
      '';
      mtu = toString (client.mtu or row.handoff.mtu or 1492);
    in
    {
      name = peerName;
      value = {
        inherit unitName;
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
            ${pkgs.iproute2}/bin/ip link set ${lib.escapeShellArg interfaceName} up
            user="$(${pkgs.coreutils}/bin/cat ${lib.escapeShellArg usernameFile})"
            pass="$(${pkgs.coreutils}/bin/cat ${lib.escapeShellArg passwordFile})"
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
            defaultroute
            replacedefaultroute
            usepeerdns
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
    };

  clientPeers = builtins.listToAttrs (map clientPeerFor clientRows);
in
{
  config = lib.optionalAttrs (clientRows != [ ]) {
    environment.systemPackages = [
            pkgs.ppp
    ];
    networking.useDHCP = lib.mkForce false;
    services.resolved.enable = lib.mkForce false;
    services.pppd = {
      enable = true;
      package = pkgs.ppp;
      peers = builtins.mapAttrs (_: row: row.peer) clientPeers;
    };
    systemd.services = builtins.listToAttrs (
      map (row: {
        name = row.unitName;
        value = row.service;
      }) (builtins.attrValues clientPeers)
    );
  };
}
