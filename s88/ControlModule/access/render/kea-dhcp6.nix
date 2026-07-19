{
  lib,
  pkgs,
  scope,
}:

let
  cfgFile = "/run/etc/kea/${scope.fileStem}-dhcp6.json";
  lease =
    (import ./lease-state.nix {
      service = "DHCPv6";
      fileStem = scope.fileStem;
      suffix = "-dhcp6";
    })
      (scope.leaseState or null);
  reservationSource =
    if (scope.reservationSource or null) == null then
      null
    else if builtins.isAttrs scope.reservationSource then
      scope.reservationSource
    else
      throw "NixOS DHCPv6 renderer requires scope.reservationSource to be an opaque protected-source record";
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
      throw "NixOS DHCPv6 renderer requires the explicit gamp-protected-reservation-set-v1 source contract";
  namePublication =
    if runtimeReservationsEnabled && builtins.isAttrs (reservationSource.namePublication or null) then
      reservationSource.namePublication
    else
      null;
  protectedNamePublicationEnabled = namePublication != null;
  protectedNamePublicationFile = "/run/protected-reservation-dns/${scope.fileStem}.conf";
  reservations = map (
    reservation:
    (
      if builtins.isString (reservation.duid or null) && reservation.duid != "" then
        { duid = reservation.duid; }
      else
        { "hw-address" = reservation.mac; }
    )
    // {
      "ip-addresses" = [ reservation.address ];
    }
    //
      lib.optionalAttrs (builtins.isString (reservation.hostname or null) && reservation.hostname != "")
        {
          hostname = reservation.hostname;
        }
  ) (scope.reservations or [ ]);

  configJson = builtins.toJSON {
    Dhcp6 = {
      "interfaces-config" = {
        interfaces = [ scope.interfaceName ];
      };

      "lease-database" = {
        type = "memfile";
        persist = lease.persist;
        name = lease.path;
      };

      subnet6 = [
        {
          id = scope.subnetId;
          interface = scope.interfaceName;
          subnet = scope.subnet;
          pools = [
            {
              pool = scope.pool;
            }
          ];
          "option-data" = [
            {
              name = "dns-servers";
              data = builtins.concatStringsSep ", " scope.dnsServers;
            }
            {
              name = "domain-search";
              data = scope.domain;
            }
          ];
          inherit reservations;
        }
      ];
    };
  };

  configTemplate = pkgs.writeText "kea-dhcp6-${scope.fileStem}-template.json" configJson;
  materializerScope =
    if builtins.isString (scope.scopeId or null) && scope.scopeId != "" then
      scope.scopeId
    else
      scope.fileStem;
  materializerArgs = [
    "--family"
    "ipv6"
    "--scope"
    materializerScope
    "--subnet"
    scope.subnet
    "--pool"
    scope.pool
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
  ]
  ++ lib.optionals protectedNamePublicationEnabled (
    [
      "--dns-output"
      protectedNamePublicationFile
      "--dns-namespace"
      namePublication.namespace
      "--dns-group"
      "unbound"
    ]
    ++ lib.concatMap (recordClass: [ "--dns-record-class" recordClass ]) namePublication.recordClasses
  );
  genConfig = "${pkgs.python3Minimal}/bin/python3 ${./runtime-reservation-materializer.py} ${lib.escapeShellArgs materializerArgs}";

  waitIface = "${pkgs.runtimeShell} ${./wait-interface-ready.sh}";
  postCheck = "${pkgs.runtimeShell} ${./kea-listener-ready.sh}";
  firewallService = "nft-allow-dhcp6-${scope.fileStem}";
  firewallComment = "allow-dhcp6-service-${scope.fileStem}";
  firewallCommand = "${pkgs.runtimeShell} ${./allow-dhcp-service.sh} ${
    lib.escapeShellArgs [
      "ipv6"
      scope.interfaceName
      "547"
      firewallComment
    ]
  }";
in
{
  environment.systemPackages = [
    pkgs.kea
    pkgs.iproute2
    pkgs.gnugrep
    pkgs.coreutils
  ];

  systemd.services."gen-kea-dhcp6-${scope.fileStem}" = {
    wantedBy = [ "multi-user.target" ];
    before = [ "kea-dhcp6-${scope.fileStem}.service" ] ++ lib.optional protectedNamePublicationEnabled "unbound.service";
    serviceConfig = {
      Type = "oneshot";
      ExecStart = genConfig;
      RemainAfterExit = true;
    };
  };

  systemd.services."${firewallService}" = {
    description = "Allow DHCPv6 service traffic on ${scope.interfaceName}";
    wantedBy = [ "multi-user.target" ];
    before = [ "kea-dhcp6-${scope.fileStem}.service" ];
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

  systemd.services."kea-dhcp6-${scope.fileStem}" = {
    description = "Kea DHCPv6 on ${scope.interfaceName}";
    wantedBy = [ "multi-user.target" ];
    after = [
      "systemd-networkd.service"
      "gen-kea-dhcp6-${scope.fileStem}.service"
      "${firewallService}.service"
    ];
    requires = [
      "systemd-networkd.service"
      "gen-kea-dhcp6-${scope.fileStem}.service"
      "${firewallService}.service"
    ];

    path = [
      pkgs.coreutils
      pkgs.iproute2
      pkgs.gnugrep
    ];

    serviceConfig = {
      Type = "simple";

      ExecStartPre = [
        "${waitIface} ${lib.escapeShellArg scope.interfaceName}"
      ];

      ExecStart = "${pkgs.kea}/bin/kea-dhcp6 -d -c ${cfgFile}";

      ExecStartPost = [
        "${postCheck} 547"
      ];

      Restart = "always";
      RestartSec = "2s";

      RuntimeDirectory = "kea";
      StateDirectory = "kea";

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
