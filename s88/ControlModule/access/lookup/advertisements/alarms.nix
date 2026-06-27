{ lib
, isa
, containerDisplayName
, roleName
, interfaceEntries
, interfaceLabelForEntry
, derivedDhcp4Entries
, derivedRadvdEntries
, haveAuthoritativeAdvertisements
,
}:

let
  incompleteDhcp4Alarms = map
    (
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
    )
    (lib.filter (entry: entry.dhcp4EnabledRequested && !entry.dhcp4Renderable) interfaceEntries);

  incompleteRadvdAlarms = map
    (
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
    )
    (lib.filter (entry: entry.radvdEnabledRequested && !entry.radvdRenderable) interfaceEntries);

  derivedAlarms = [ ];

  alarms = derivedAlarms ++ incompleteDhcp4Alarms ++ incompleteRadvdAlarms;

  failureMessages = isa.warningsFromAlarms alarms;

  failClosedWarnings =
    if failureMessages == [ ] then
      [ ]
    else
      throw ''
        FS-310-HDS-010-SDS-010-SMS-110: network-renderer-nixos fail-closed advertisement contract violation.
        The renderer detected incomplete advertisement data that would require renderer-only assumptions.
        CPM must provide authoritative DHCPv4/IPv6 RA advertisement interface binding, prefixes/subnets, and DNS data before emission.

        ${lib.concatStringsSep "\n\n" failureMessages}
      '';
in
{
  inherit alarms;
  warnings = failClosedWarnings;
}
