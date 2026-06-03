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

  clientServiceFor =
    row:
    let
      client = row.pppoe.client;
      server = row.pppoe.server;
      logicalIf = client.coreInterface;
      interfaceName = ifaceNameFor logicalIf;
      serviceName = "s88-pppoe-client-${logicalIf}";
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
      secretsScript = ''
        user="$(${pkgs.coreutils}/bin/cat ${lib.escapeShellArg usernameFile})"
        pass="$(${pkgs.coreutils}/bin/cat ${lib.escapeShellArg passwordFile})"
        ${pkgs.coreutils}/bin/install -m 0600 /dev/null /run/ppp/chap-secrets
        ${pkgs.coreutils}/bin/install -m 0600 /dev/null /run/ppp/pap-secrets
        printf '%s * %s *\n' "$user" "$pass" > /run/ppp/chap-secrets
        printf '%s * %s *\n' "$user" "$pass" > /run/ppp/pap-secrets
      '';
    in
    {
      name = serviceName;
      value = {
        description = "S88 PPPoE client on ${interfaceName}";
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
          ${pkgs.coreutils}/bin/mkdir -p /run/ppp
          ${pkgs.iproute2}/bin/ip link set ${lib.escapeShellArg interfaceName} up
          ${secretsScript}
          exec ${pkgs.ppp}/bin/pppd \
            pty "${pkgs.rp-pppoe}/bin/pppoe -I ${interfaceName}" \
            user s88-lab \
            noauth \
            noipdefault \
            defaultroute \
            replacedefaultroute \
            usepeerdns \
            persist \
            maxfail 0 \
            mtu ${mtu} \
            mru ${mtu} \
            ip-up-script ${ipUp} \
            nodetach
        '';
      };
    };

  clientServices = builtins.listToAttrs (map clientServiceFor clientRows);
in
{
  config = lib.optionalAttrs (clientRows != [ ]) {
    environment.systemPackages = [
            pkgs.ppp
            pkgs.rp-pppoe
    ];
    networking.useDHCP = lib.mkForce false;
    services.resolved.enable = lib.mkForce false;
    systemd.services = clientServices;
  };
}
