{ lib, containerModel }:

let
  isa = import ../../alarm/isa18.nix { inherit lib; };
  common = import ./advertisements/common.nix { inherit lib; };
  context = import ./advertisements/context.nix { inherit containerModel; };

  interfaces = import ./advertisements/interfaces.nix {
    inherit lib containerModel common;
    inherit (context)
      containerInterfaces
      runtimeInterfaces
      defaultDhcp4Advertise
      defaultRadvdAdvertise
      ;
  };

  authoritative = import ./advertisements/authoritative.nix {
    inherit lib common;
    inherit (context)
      runtimeTarget
      currentSiteIpv6
      currentInventorySiteIpv6
      ;
    inherit (interfaces) resolveAuthoritativeInterfaceName;
  };

  derived = import ./advertisements/derived.nix {
    inherit lib common;
    inherit (interfaces) interfaceEntries;
  };

  alarms = import ./advertisements/alarms.nix {
    inherit lib isa;
    inherit (context) containerDisplayName roleName;
    inherit (interfaces) interfaceEntries interfaceLabelForEntry;
    inherit (derived) derivedDhcp4Entries derivedRadvdEntries;
    inherit (authoritative) haveAuthoritativeAdvertisements;
  };
in
{
  dhcp4Scopes =
    if authoritative.haveAuthoritativeAdvertisements then
      authoritative.authoritativeDhcp4Scopes
    else
      derived.dhcp4Scopes;

  radvdScopes =
    if authoritative.haveAuthoritativeAdvertisements then
      authoritative.authoritativeRadvdScopes
    else
      derived.radvdScopes;

  inherit (alarms) alarms warnings;
}
