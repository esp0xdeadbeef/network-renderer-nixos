{
  lib,
  containerModel,
  containerInterfaces,
  runtimeInterfaces,
  defaultDhcp4Advertise,
  defaultRadvdAdvertise,
  common,
}:

let
  inherit
    (common)
    sortedAttrNames
    mergeAttrs
    firstOrNull
    ipv4AddressFromCIDR
    defaultIPv4Pool
    boolField
    stringField
    stringListField
    safeStem
    ;

  actualInterfaceNameFor =
    iface:
    if iface ? containerInterfaceName && builtins.isString iface.containerInterfaceName && iface.containerInterfaceName != "" then
      iface.containerInterfaceName
    else if iface ? interfaceName && builtins.isString iface.interfaceName && iface.interfaceName != "" then
      iface.interfaceName
    else if iface ? hostInterfaceName && builtins.isString iface.hostInterfaceName && iface.hostInterfaceName != "" then
      iface.hostInterfaceName
    else if iface ? renderedIfName && builtins.isString iface.renderedIfName && iface.renderedIfName != "" then
      iface.renderedIfName
    else if iface ? ifName && builtins.isString iface.ifName && iface.ifName != "" then
      iface.ifName
    else
      null;

  interfaceMatchesName =
    iface: name:
    builtins.isString name
    && name != ""
    && (
      (iface ? ifName && builtins.isString iface.ifName && iface.ifName == name)
      || (iface ? containerInterfaceName && builtins.isString iface.containerInterfaceName && iface.containerInterfaceName == name)
      || (iface ? interfaceName && builtins.isString iface.interfaceName && iface.interfaceName == name)
      || (iface ? hostInterfaceName && builtins.isString iface.hostInterfaceName && iface.hostInterfaceName == name)
      || (iface ? renderedIfName && builtins.isString iface.renderedIfName && iface.renderedIfName == name)
    );

  semanticInterfaceFor =
    { containerIface, runtimeIface }:
    if containerIface ? semanticInterface && builtins.isAttrs containerIface.semanticInterface then
      containerIface.semanticInterface
    else if runtimeIface ? semanticInterface && builtins.isAttrs runtimeIface.semanticInterface then
      runtimeIface.semanticInterface
    else if containerIface ? semantic && builtins.isAttrs containerIface.semantic then
      containerIface.semantic
    else if runtimeIface ? semantic && builtins.isAttrs runtimeIface.semantic then
      runtimeIface.semantic
    else
      { };

  sourceKindFor =
    { containerIface, runtimeIface, semanticInterface }:
    if semanticInterface ? kind && builtins.isString semanticInterface.kind then
      semanticInterface.kind
    else if containerIface ? sourceKind && builtins.isString containerIface.sourceKind then
      containerIface.sourceKind
    else if runtimeIface ? sourceKind && builtins.isString runtimeIface.sourceKind then
      runtimeIface.sourceKind
    else if containerIface ? connectivity && builtins.isString (containerIface.connectivity.sourceKind or null) then
      containerIface.connectivity.sourceKind
    else if runtimeIface ? connectivity && builtins.isString (runtimeIface.connectivity.sourceKind or null) then
      runtimeIface.connectivity.sourceKind
    else
      null;

  entryFor =
    ifName:
    let
      containerIface = containerInterfaces.${ifName};
      runtimeIface = if builtins.hasAttr ifName runtimeInterfaces then runtimeInterfaces.${ifName} else { };
      semanticInterface = semanticInterfaceFor { inherit containerIface runtimeIface; };
      interfaceName = actualInterfaceNameFor containerIface;
      sourceKind = sourceKindFor { inherit containerIface runtimeIface semanticInterface; };
      isLocalAdapter = sourceKind != "wan" && sourceKind != "p2p";
      addresses = containerIface.addresses or (runtimeIface.addresses or [ ]);
      ipv4Cidrs = lib.filter (value: builtins.isString value && lib.hasInfix "." value && lib.hasInfix "/" value) addresses;
      ipv6Cidrs = lib.filter (value: builtins.isString value && lib.hasInfix ":" value && lib.hasInfix "/" value) addresses;
      firstIPv4Cidr = firstOrNull ipv4Cidrs;
      firstIPv6Cidr = firstOrNull ipv6Cidrs;
      serviceSettings = mergeAttrs [
        (containerIface.serviceAdvertisements or { })
        (containerIface.advertise or { })
        (runtimeIface.serviceAdvertisements or { })
        (runtimeIface.advertise or { })
      ];
      dhcp4Settings = mergeAttrs [
        (serviceSettings.dhcp4 or { })
        (containerIface.dhcp4 or { })
        (runtimeIface.dhcp4 or { })
      ];
      radvdSettings = mergeAttrs [
        (serviceSettings.radvd or { })
        (serviceSettings.ra or { })
        (serviceSettings.ipv6Ra or { })
        (containerIface.radvd or { })
        (containerIface.ra or { })
        (containerIface.ipv6Ra or { })
        (runtimeIface.radvd or { })
        (runtimeIface.ra or { })
        (runtimeIface.ipv6Ra or { })
      ];
      dhcp4EnabledRequested = boolField dhcp4Settings [ "enable" ] (defaultDhcp4Advertise && isLocalAdapter);
      radvdEnabledRequested = boolField radvdSettings [ "enable" ] (defaultRadvdAdvertise && isLocalAdapter);
      ipv4Address = ipv4AddressFromCIDR firstIPv4Cidr;
      explicitSubnet4 = if builtins.isString (semanticInterface.subnet4 or null) then semanticInterface.subnet4 else null;
      explicitSubnet6 = if builtins.isString (semanticInterface.subnet6 or null) then semanticInterface.subnet6 else null;
      advertisedIpv6Prefixes =
        if semanticInterface ? ra6Prefixes && builtins.isList semanticInterface.ra6Prefixes then
          map toString semanticInterface.ra6Prefixes
        else
          [ ];
      dhcp4Subnet = stringField dhcp4Settings [ "subnet" "cidr" ] (if explicitSubnet4 != null then explicitSubnet4 else firstIPv4Cidr);
      dhcp4Pool = stringField dhcp4Settings [ "pool" ] (defaultIPv4Pool ipv4Address);
      dhcp4Router = stringField dhcp4Settings [ "router" "gateway" ] ipv4Address;
      dhcp4DnsServers = stringListField dhcp4Settings [ "dnsServers" "nameServers" ] (lib.optionals (dhcp4Router != null) [ dhcp4Router ]);
      dhcp4Domain = stringField dhcp4Settings [ "domain" "domainName" ] "lan.";
      radvdPrefixes = stringListField radvdSettings [ "prefixes" ] (if advertisedIpv6Prefixes != [ ] then advertisedIpv6Prefixes else if explicitSubnet6 != null then [ explicitSubnet6 ] else ipv6Cidrs);
      radvdRdnss = stringListField radvdSettings [ "rdnss" "dnsServers" ] (lib.optionals (firstIPv6Cidr != null) [ (ipv4AddressFromCIDR firstIPv6Cidr) ]);
      radvdDomain = stringField radvdSettings [ "domain" "dnssl" "domainName" ] "lan.";
      dhcp4Renderable = dhcp4EnabledRequested && interfaceName != null && dhcp4Subnet != null && dhcp4Pool != null && dhcp4Router != null && dhcp4DnsServers != [ ];
      radvdRenderable = radvdEnabledRequested && interfaceName != null && radvdPrefixes != [ ] && radvdRdnss != [ ];
      base = {
        inherit ifName interfaceName sourceKind isLocalAdapter semanticInterface;
        inherit dhcp4EnabledRequested radvdEnabledRequested dhcp4Renderable radvdRenderable;
        derivedDhcp4 = dhcp4Renderable && dhcp4Settings == { };
        derivedRadvd = radvdRenderable && radvdSettings == { };
        stem = safeStem ifName;
      };
    in
    base
    // lib.optionalAttrs dhcp4Renderable {
      dhcp4 = {
        serviceName = "lan-${base.stem}";
        fileStem = base.stem;
        interfaceKey = ifName;
        inherit interfaceName;
        subnet = dhcp4Subnet;
        pool = dhcp4Pool;
        router = dhcp4Router;
        dnsServers = dhcp4DnsServers;
        domain = dhcp4Domain;
      };
    }
    // lib.optionalAttrs radvdRenderable {
      radvd = {
        serviceName = "lan-${base.stem}";
        fileStem = base.stem;
        interfaceKey = ifName;
        inherit interfaceName;
        prefixes = radvdPrefixes;
        rdnss = radvdRdnss;
        domain = radvdDomain;
      };
    };
in
{
  interfaceEntries = map entryFor (sortedAttrNames containerInterfaces);

  interfaceLabelForEntry =
    entry:
    if entry.interfaceName != null && entry.interfaceName != entry.ifName then
      "${entry.ifName} -> ${entry.interfaceName}"
    else
      entry.ifName;

  resolveAuthoritativeInterfaceName =
    rawName:
    if !(builtins.isString rawName) || rawName == "" then
      null
    else if builtins.hasAttr rawName containerInterfaces then
      let resolved = actualInterfaceNameFor containerInterfaces.${rawName}; in if resolved != null then resolved else rawName
    else if builtins.hasAttr rawName runtimeInterfaces then
      let resolved = actualInterfaceNameFor runtimeInterfaces.${rawName}; in if resolved != null then resolved else rawName
    else
      let
        matches =
          (lib.filter (iface: interfaceMatchesName iface rawName) (builtins.attrValues runtimeInterfaces))
          ++ (lib.filter (iface: interfaceMatchesName iface rawName) (builtins.attrValues containerInterfaces));
      in
      if builtins.length matches >= 1 then
        let resolved = actualInterfaceNameFor (builtins.head matches); in if resolved != null then resolved else rawName
      else
        rawName;
}
