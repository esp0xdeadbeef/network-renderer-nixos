{
  lib,
  isa,
  containerDisplayName,
  roleName,
  interfaceEntries,
  interfaceLabelForEntry,
  derivedDhcp4Entries,
  derivedRadvdEntries,
  haveAuthoritativeAdvertisements,
}:

let
  incompleteDhcp4Alarms = map (
    entry:
    isa.mkDesignAssumptionAlarm {
      alarmId = "access-dhcp4-incomplete-${entry.stem}";
      summary = "DHCPv4 advertisement was requested but rendered interface data is incomplete";
      file = "s88/ControlModule/access/lookup/advertisements.nix";
      entityName = containerDisplayName;
      roleName = roleName;
      interfaces = [ (interfaceLabelForEntry entry) ];
      assumptions = [
        "DHCPv4 advertisement enablement was resolved true from role defaults or per-interface advertisement overrides"
        "renderer expected authoritative DHCPv4 interface binding, subnet, pool, router, and DNS data to exist before emission"
        "renderer will not silently invent a partial DHCPv4 scope when the available rendered data is insufficient"
      ];
      authorityText = "Control plane should provide authoritative DHCP settings.";
    }
  ) (lib.filter (entry: entry.dhcp4EnabledRequested && !entry.dhcp4Renderable) interfaceEntries);

  incompleteRadvdAlarms = map (
    entry:
    isa.mkDesignAssumptionAlarm {
      alarmId = "access-radvd-incomplete-${entry.stem}";
      summary = "IPv6 RA advertisement was requested but rendered interface data is incomplete";
      file = "s88/ControlModule/access/lookup/advertisements.nix";
      entityName = containerDisplayName;
      roleName = roleName;
      interfaces = [ (interfaceLabelForEntry entry) ];
      assumptions = [
        "IPv6 RA advertisement enablement was resolved true from role defaults or per-interface advertisement overrides"
        "renderer expected authoritative IPv6 advertisement interface binding, prefixes, and RDNSS data to exist before emission"
        "renderer will not silently invent a partial IPv6 advertisement when the available rendered data is insufficient"
      ];
      authorityText = "Control plane should provide authoritative IPv6 advertisement settings.";
    }
  ) (lib.filter (entry: entry.radvdEnabledRequested && !entry.radvdRenderable) interfaceEntries);

  derivedAlarms =
    lib.optionals (!haveAuthoritativeAdvertisements && derivedDhcp4Entries != [ ]) [
      (isa.mkDesignAssumptionAlarm {
        alarmId = "access-dhcp4-derived";
        summary = "DHCPv4 advertisement still defaults from renderer policy when explicit DHCP allocation data is absent";
        file = "s88/ControlModule/access/lookup/advertisements.nix";
        entityName = containerDisplayName;
        roleName = roleName;
        interfaces = map interfaceLabelForEntry derivedDhcp4Entries;
        assumptions = [
          "advertisement enablement defaults from the role/container profile when no authoritative DHCP policy exists"
          "tenant-facing interfaces are selected from explicit interface semantics when available, otherwise from rendered local-adapter classification"
          "the service bind interface defaults from the rendered container binding of that selected interface"
          "the served subnet defaults from the explicit tenant subnet when available, otherwise from the rendered IPv4 CIDR"
          "the DHCP pool is synthesized from the rendered interface IPv4 address as x.y.z.100 - x.y.z.200"
          "the default router/gateway is set to the rendered interface IPv4 address"
          "DNS servers default to that same rendered IPv4 address"
          "the DHCP search/domain name defaults to 'lan.'"
          "Kea subnet identifiers default from stable interface ordering rather than authoritative DHCP allocation identity"
        ];
        authorityText = "Control plane should provide authoritative DHCP allocation data.";
      })
    ]
    ++ lib.optionals (!haveAuthoritativeAdvertisements && derivedRadvdEntries != [ ]) [
      (isa.mkDesignAssumptionAlarm {
        alarmId = "access-radvd-derived";
        summary = "IPv6 RA advertisement still defaults from renderer policy when explicit IPv6 advertisement data is absent";
        file = "s88/ControlModule/access/lookup/advertisements.nix";
        entityName = containerDisplayName;
        roleName = roleName;
        interfaces = map interfaceLabelForEntry derivedRadvdEntries;
        assumptions = [
          "advertisement enablement defaults from the role/container profile when no authoritative IPv6 advertisement policy exists"
          "tenant-facing interfaces are selected from explicit interface semantics when available, otherwise from rendered local-adapter classification"
          "the service bind interface defaults from the rendered container binding of that selected interface"
          "advertised prefixes default from the explicit tenant subnet when available, otherwise from rendered IPv6 CIDRs"
          "RDNSS defaults to the first rendered IPv6 address on the interface"
          "the advertised DNSSL/domain defaults to 'lan.'"
        ];
        authorityText = "Control plane should provide authoritative IPv6 advertisement data.";
      })
    ];

  alarms = derivedAlarms ++ incompleteDhcp4Alarms ++ incompleteRadvdAlarms;
in
{
  inherit alarms;
  warnings = isa.warningsFromAlarms alarms;
}
