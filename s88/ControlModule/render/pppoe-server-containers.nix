{ lib, cpm, hostName, hostPlan ? { } }:

let
  data =
    if cpm ? control_plane_model && builtins.isAttrs cpm.control_plane_model then
      cpm.control_plane_model.data or { }
    else
      { };

  siteRows =
    lib.concatLists (
      lib.mapAttrsToList
        (
          _enterprise: sites:
          if !builtins.isAttrs sites then
            [ ]
          else
            lib.concatLists (
              lib.mapAttrsToList
                (
                  _siteName: site:
                  if builtins.isAttrs (site.upstreamEmulation or null) then
                    builtins.attrValues site.upstreamEmulation
                  else
                    [ ]
                )
                sites
            )
        )
        data
    );

  pppoeServerRows =
    lib.filter
      (
        row:
        let client = ((row.pppoe or { }).client or { });
        in
        (row.mode or null) == "pppoe"
        && (row.backend or null) == "nixos"
        && (row.pppoe or { }) ? server
        && (row.pppoe or { }) ? client
        && builtins.elem (client.coreNode or null) (hostPlan.selectedUnits or [ ])
      )
      siteRows;

  serverContainerFor =
    row:
    let
      server = row.pppoe.server;
      handoff = row.handoff or { };
      containerName = server.node;
      serviceName = "s88-pppoe-server";
      usernameFile = server.credentials.usernameFile;
      passwordFile = server.credentials.passwordFile;
      providerAddress = server.session.providerAddress;
      customerAddress = server.session.customerAddress;
    in
    {
      name = containerName;
      value = {
        autoStart = true;
        privateNetwork = true;
        hostBridge = handoff.bridge;
        bindMounts = { };
        extraVeths = { };
        allowedDevices = [ ];
        additionalCapabilities = [
          "CAP_NET_ADMIN"
          "CAP_NET_RAW"
        ];
        config =
          { lib, pkgs, ... }:
          {
            boot.isContainer = true;
            networking.useNetworkd = true;
            systemd.network.enable = true;
            networking.useDHCP = false;
            networking.firewall.enable = lib.mkForce false;
            networking.useHostResolvConf = lib.mkForce false;
            services.resolved.enable = lib.mkForce false;
            networking.hostName = containerName;
            environment.systemPackages = [
              pkgs.iproute2
              pkgs.ppp
              pkgs.rp-pppoe
            ];
            environment.etc."s88/pppoe-tools".text = ''
              pppoe-server=${pkgs.rp-pppoe}/bin/pppoe-server
              pppoe=${pkgs.rp-pppoe}/bin/pppoe
              pppoe-sniff=${pkgs.rp-pppoe}/bin/pppoe-sniff
              pppd=${pkgs.ppp}/bin/pppd
            '';
            system.stateVersion = "25.11";
            systemd.services.${serviceName} = {
              description = "S88 PPPoE access concentrator on ${handoff.bridge}";
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
                ${pkgs.iproute2}/bin/ip link set eth0 up
                ${pkgs.coreutils}/bin/test -x ${pkgs.rp-pppoe}/bin/pppoe-sniff
                ${pkgs.coreutils}/bin/mkdir -p /etc/ppp
                user="$(${pkgs.coreutils}/bin/cat ${lib.escapeShellArg usernameFile})"
                pass="$(${pkgs.coreutils}/bin/cat ${lib.escapeShellArg passwordFile})"
                ${pkgs.coreutils}/bin/install -m 0600 /dev/null /etc/ppp/chap-secrets
                ${pkgs.coreutils}/bin/install -m 0600 /dev/null /etc/ppp/pap-secrets
                printf '%s * %s *\n' "$user" "$pass" > /etc/ppp/chap-secrets
                printf '* * %s *\n' "$pass" >> /etc/ppp/chap-secrets
                printf '%s * %s *\n' "$user" "$pass" > /etc/ppp/pap-secrets
                printf '* * %s *\n' "$pass" >> /etc/ppp/pap-secrets
                ${pkgs.coreutils}/bin/cat > /etc/ppp/s88-pppoe-server-options <<EOF
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
                ms-dns ${providerAddress}
                EOF
                exec ${pkgs.rp-pppoe}/bin/pppoe-server \
                  -I eth0 \
                  -L ${lib.escapeShellArg providerAddress} \
                  -R ${lib.escapeShellArg customerAddress} \
                  -O /etc/ppp/s88-pppoe-server-options \
                  -q ${pkgs.ppp}/bin/pppd \
                  -Q ${pkgs.rp-pppoe}/bin/pppoe \
                  -N 32
              '';
            };
          };
        specialArgs = {
          deploymentHostName = hostName;
          s88RoleName = "pppoe-access-concentrator";
          unitName = containerName;
          s88Warnings = [
            "FS-800 NixOS PPPoE server uses rp-pppoe because accel-ppp is not present in the current nixpkgs input"
            "FS-800 NixOS PPPoE emulated-ISP image includes rp-pppoe pppoe-sniff for handoff debugging"
          ];
          s88Alarms = [ ];
        };
      };
    };
in
builtins.listToAttrs (map serverContainerFor pppoeServerRows)
