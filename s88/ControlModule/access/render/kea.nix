{
  lib,
  pkgs,
  scope,
}:

let
  cfgFile = "/run/etc/kea/${scope.fileStem}.json";
  lease =
    (import ./lease-state.nix {
      service = "DHCPv4";
      fileStem = scope.fileStem;
    })
      (scope.leaseState or null);
  requiredLeaseDnsField =
    name: value:
    if builtins.isString value && value != "" then
      value
    else
      throw "NixOS DHCPv4 renderer requires scope.leaseDns.${name} before lease hostnames may be published to DNS";
  leaseDns =
    if (scope.leaseDns or null) == null then
      null
    else if builtins.isAttrs scope.leaseDns then
      let
        rawNamespace = requiredLeaseDnsField "namespace" (scope.leaseDns.namespace or null);
        namespace = if lib.hasSuffix "." rawNamespace then rawNamespace else "${rawNamespace}.";
      in
      {
        ownerScope = requiredLeaseDnsField "ownerScope" (scope.leaseDns.ownerScope or null);
        requesterScope = requiredLeaseDnsField "requesterScope" (scope.leaseDns.requesterScope or null);
        inherit namespace;
      }
    else
      throw "NixOS DHCPv4 renderer requires scope.leaseDns to be an explicit owner/requester namespace contract";
  syncEnabled = leaseDns != null;
  reservationSource =
    if (scope.reservationSource or null) == null then
      null
    else if builtins.isAttrs scope.reservationSource then
      scope.reservationSource
    else
      throw "NixOS DHCPv4 renderer requires scope.reservationSource to be an opaque protected-source record";
  runtimeReservationsEnabled = reservationSource != null;
  runtimeReservationSourceFile =
    if !runtimeReservationsEnabled then
      null
    else if
      (reservationSource.schema or null) == "gamp-protected-reservation-set-v1"
      && (reservationSource.sourceClass or null) == "protected"
      && builtins.isString (reservationSource.sourceFile or null)
      && reservationSource.sourceFile != ""
    then
      reservationSource.sourceFile
    else
      throw "NixOS DHCPv4 renderer requires the explicit gamp-protected-reservation-set-v1 source contract";
  reservations = map (
    reservation:
    {
      "hw-address" = reservation.mac;
      "ip-address" = reservation.address;
    }
    //
      lib.optionalAttrs (builtins.isString (reservation.hostname or null) && reservation.hostname != "")
        {
          hostname = reservation.hostname;
        }
  ) (scope.reservations or [ ]);

  configJson = builtins.toJSON {
    Dhcp4 = {
      "interfaces-config" = {
        interfaces = [ scope.interfaceName ];
      };

      "lease-database" = {
        type = "memfile";
        persist = lease.persist;
        name = lease.path;
      };

      subnet4 = [
        {
          id = scope.subnetId;
          subnet = scope.subnet;
          pools = [
            {
              pool = scope.pool;
            }
          ];
          "option-data" = [
            {
              name = "routers";
              data = scope.router;
            }
            {
              name = "domain-name-servers";
              data = builtins.concatStringsSep ", " scope.dnsServers;
            }
            {
              name = "domain-name";
              data = scope.domain;
            }
          ];
          inherit reservations;
        }
      ];
    };
  };

  configTemplate = pkgs.writeText "kea-${scope.fileStem}-template.json" configJson;
  materializerScope =
    if builtins.isString (scope.scopeId or null) && scope.scopeId != "" then
      scope.scopeId
    else
      scope.fileStem;
  materializerArgs = [
    "--family"
    "ipv4"
    "--scope"
    materializerScope
    "--subnet"
    scope.subnet
    "--template"
    (builtins.toString configTemplate)
    "--output"
    cfgFile
    "--lease-directory"
    lease.directory
  ]
  ++ lib.optionals runtimeReservationsEnabled [
    "--source"
    runtimeReservationSourceFile
  ];
  genConfig = "${pkgs.python3Minimal}/bin/python3 ${./runtime-reservation-materializer.py} ${lib.escapeShellArgs materializerArgs}";
  syncScript = "${pkgs.runtimeShell} ${./kea-unbound-sync.sh}";

  waitIface = "${pkgs.runtimeShell} ${./wait-interface-ready.sh}";
  postCheck = "${pkgs.runtimeShell} ${./kea-listener-ready.sh}";
  firewallService = "nft-allow-dhcp4-${scope.fileStem}";
  firewallComment = "allow-dhcp4-service-${scope.fileStem}";
  firewallCommand = "${pkgs.runtimeShell} ${./allow-dhcp-service.sh} ${
    lib.escapeShellArgs [
      "ipv4"
      scope.interfaceName
      "67"
      firewallComment
    ]
  }";
in
{
  environment.systemPackages = [
    pkgs.kea
    pkgs.iproute2
    pkgs.gnugrep
    pkgs.gawk
    pkgs.coreutils
  ]
  ++ lib.optional syncEnabled pkgs.unbound;

  systemd.services = {
    "gen-kea-${scope.fileStem}" = {
      wantedBy = [ "multi-user.target" ];
      before = [ "kea-dhcp4-${scope.fileStem}.service" ];
      serviceConfig = {
        Type = "oneshot";
        ExecStart = genConfig;
        RemainAfterExit = true;
      };
    };

    "${firewallService}" = {
      description = "Allow DHCPv4 service traffic on ${scope.interfaceName}";
      wantedBy = [ "multi-user.target" ];
      before = [ "kea-dhcp4-${scope.fileStem}.service" ];
      after = [ "nftables.service" ];
      requires = [ "nftables.service" ];
      path = [
        pkgs.coreutils
        pkgs.gnugrep
        pkgs.nftables
      ];
      serviceConfig = {
        Type = "oneshot";
        ExecStart = firewallCommand;
        RemainAfterExit = true;
      };
    };

    "kea-dhcp4-${scope.fileStem}" = {
      description = "Kea DHCPv4 on ${scope.interfaceName}";
      wantedBy = [ "multi-user.target" ];
      after = [
        "systemd-networkd.service"
        "gen-kea-${scope.fileStem}.service"
        "${firewallService}.service"
      ]
      ++ lib.optional syncEnabled "unbound.service";
      requires = [
        "systemd-networkd.service"
        "gen-kea-${scope.fileStem}.service"
        "${firewallService}.service"
      ];
      wants = lib.optional syncEnabled "unbound.service";

      path = [
        pkgs.coreutils
        pkgs.iproute2
        pkgs.gnugrep
        pkgs.gawk
      ];

      serviceConfig = {
        Type = "simple";

        ExecStartPre = [
          "${waitIface} ${lib.escapeShellArg scope.interfaceName}"
        ];

        ExecStart = "${pkgs.kea}/bin/kea-dhcp4 -d -c ${cfgFile}";

        ExecStartPost = [
          "${postCheck} 67"
        ];

        Restart = "always";
        RestartSec = "2s";

        RuntimeDirectory = "kea";

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
  // lib.optionalAttrs syncEnabled {
    "kea-unbound-sync-${scope.fileStem}" = {
      description = "Publish Kea DHCPv4 lease hostnames to Unbound for ${scope.interfaceName}";
      environment = {
        LEASE_FILE = lease.path;
        NAMESPACE = leaseDns.namespace;
        OWNER_SCOPE = leaseDns.ownerScope;
        REQUESTER_SCOPE = leaseDns.requesterScope;
        UNBOUND_CONTROL = "${pkgs.unbound}/bin/unbound-control";
      };
      after = [
        "kea-dhcp4-${scope.fileStem}.service"
        "unbound.service"
      ];
      wants = [
        "kea-dhcp4-${scope.fileStem}.service"
        "unbound.service"
      ];
      serviceConfig = {
        Type = "oneshot";
        ExecStart = syncScript;
      };
    };
  };

  systemd.timers = lib.optionalAttrs syncEnabled {
    "kea-unbound-sync-${scope.fileStem}" = {
      description = "Best-effort Kea DHCPv4 lease hostname sync for ${scope.interfaceName}";
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnBootSec = "30s";
        OnUnitActiveSec = "60s";
        Unit = "kea-unbound-sync-${scope.fileStem}.service";
      };
    };
  };
}
