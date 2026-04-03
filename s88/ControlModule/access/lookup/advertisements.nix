{ lib, containerModel }:

let
  sortedAttrNames = attrs: lib.sort builtins.lessThan (builtins.attrNames attrs);

  asStringList =
    value:
    if value == null then
      [ ]
    else if builtins.isString value then
      [ value ]
    else if builtins.isList value then
      lib.filter builtins.isString value
    else
      [ ];

  mergeAttrs =
    values:
    builtins.foldl' (acc: value: if builtins.isAttrs value then acc // value else acc) { } values;

  firstOrNull = values: if values == [ ] then null else builtins.head values;

  splitCIDR =
    cidr:
    let
      parts = lib.splitString "/" cidr;
    in
    if builtins.length parts == 2 then
      {
        address = builtins.elemAt parts 0;
        prefix = builtins.elemAt parts 1;
      }
    else
      null;

  ipv4AddressFromCIDR =
    cidr:
    let
      parsed = splitCIDR cidr;
    in
    if parsed == null then null else parsed.address;

  defaultIPv4Pool =
    ipv4Address:
    if !builtins.isString ipv4Address then
      null
    else
      let
        octets = lib.splitString "." ipv4Address;
      in
      if builtins.length octets == 4 then
        "${builtins.elemAt octets 0}.${builtins.elemAt octets 1}.${builtins.elemAt octets 2}.100 - ${builtins.elemAt octets 0}.${builtins.elemAt octets 1}.${builtins.elemAt octets 2}.200"
      else
        null;

  boolField =
    attrs: names: fallback:
    let
      values = lib.filter builtins.isBool (
        map (
          name: if builtins.isAttrs attrs && builtins.hasAttr name attrs then attrs.${name} else null
        ) names
      );
    in
    if values == [ ] then fallback else builtins.head values;

  stringField =
    attrs: names: fallback:
    let
      values = lib.filter builtins.isString (
        map (
          name: if builtins.isAttrs attrs && builtins.hasAttr name attrs then attrs.${name} else null
        ) names
      );
    in
    if values == [ ] then fallback else builtins.head values;

  stringListField =
    attrs: names: fallback:
    let
      values = lib.concatMap (
        name:
        if builtins.isAttrs attrs && builtins.hasAttr name attrs then asStringList attrs.${name} else [ ]
      ) names;
    in
    if values == [ ] then fallback else lib.unique values;

  roleName = containerModel.roleName or null;
  roleConfig =
    if containerModel ? roleConfig && builtins.isAttrs containerModel.roleConfig then
      containerModel.roleConfig
    else
      { };

  containerRoleConfig =
    if roleConfig ? container && builtins.isAttrs roleConfig.container then
      roleConfig.container
    else
      { };

  advertiseDefaults =
    if containerRoleConfig ? advertise && builtins.isAttrs containerRoleConfig.advertise then
      containerRoleConfig.advertise
    else
      { };

  defaultDhcp4Advertise =
    if advertiseDefaults ? dhcp4 && builtins.isBool advertiseDefaults.dhcp4 then
      advertiseDefaults.dhcp4
    else
      roleName == "access";

  defaultRadvdAdvertise =
    if advertiseDefaults ? radvd && builtins.isBool advertiseDefaults.radvd then
      advertiseDefaults.radvd
    else
      roleName == "access";

  containerInterfaces =
    if containerModel ? interfaces && builtins.isAttrs containerModel.interfaces then
      containerModel.interfaces
    else
      { };

  runtimeTarget =
    if containerModel ? runtimeTarget && builtins.isAttrs containerModel.runtimeTarget then
      containerModel.runtimeTarget
    else
      { };

  runtimeInterfaces =
    if runtimeTarget ? interfaces && builtins.isAttrs runtimeTarget.interfaces then
      runtimeTarget.interfaces
    else
      { };

  actualInterfaceNameFor =
    iface:
    if
      iface ? containerInterfaceName
      && builtins.isString iface.containerInterfaceName
      && iface.containerInterfaceName != ""
    then
      iface.containerInterfaceName
    else if
      iface ? interfaceName && builtins.isString iface.interfaceName && iface.interfaceName != ""
    then
      iface.interfaceName
    else if
      iface ? hostInterfaceName
      && builtins.isString iface.hostInterfaceName
      && iface.hostInterfaceName != ""
    then
      iface.hostInterfaceName
    else if
      iface ? renderedIfName && builtins.isString iface.renderedIfName && iface.renderedIfName != ""
    then
      iface.renderedIfName
    else if iface ? ifName && builtins.isString iface.ifName && iface.ifName != "" then
      iface.ifName
    else
      null;

  sourceKindFor =
    {
      containerIface,
      runtimeIface,
    }:
    if containerIface ? sourceKind && builtins.isString containerIface.sourceKind then
      containerIface.sourceKind
    else if runtimeIface ? sourceKind && builtins.isString runtimeIface.sourceKind then
      runtimeIface.sourceKind
    else if
      containerIface ? connectivity
      && builtins.isAttrs containerIface.connectivity
      && containerIface.connectivity ? sourceKind
      && builtins.isString containerIface.connectivity.sourceKind
    then
      containerIface.connectivity.sourceKind
    else if
      runtimeIface ? connectivity
      && builtins.isAttrs runtimeIface.connectivity
      && runtimeIface.connectivity ? sourceKind
      && builtins.isString runtimeIface.connectivity.sourceKind
    then
      runtimeIface.connectivity.sourceKind
    else
      null;

  safeStem = name: builtins.replaceStrings [ "/" ":" " " ] [ "-" "-" "-" ] name;

  interfaceEntries = map (
    ifName:
    let
      containerIface = containerInterfaces.${ifName};
      runtimeIface =
        if builtins.hasAttr ifName runtimeInterfaces then runtimeInterfaces.${ifName} else { };

      interfaceName = actualInterfaceNameFor containerIface;

      sourceKind = sourceKindFor {
        inherit containerIface runtimeIface;
      };

      isLocalAdapter = sourceKind != "wan" && sourceKind != "p2p";

      addresses =
        if containerIface ? addresses && builtins.isList containerIface.addresses then
          containerIface.addresses
        else if runtimeIface ? addresses && builtins.isList runtimeIface.addresses then
          runtimeIface.addresses
        else
          [ ];

      ipv4Cidrs = lib.filter (
        value: builtins.isString value && lib.hasInfix "." value && lib.hasInfix "/" value
      ) addresses;
      ipv6Cidrs = lib.filter (
        value: builtins.isString value && lib.hasInfix ":" value && lib.hasInfix "/" value
      ) addresses;

      firstIPv4Cidr = firstOrNull ipv4Cidrs;
      firstIPv6Cidr = firstOrNull ipv6Cidrs;

      serviceSettings = mergeAttrs [
        (if containerIface ? serviceAdvertisements then containerIface.serviceAdvertisements else { })
        (if containerIface ? advertise then containerIface.advertise else { })
        (if runtimeIface ? serviceAdvertisements then runtimeIface.serviceAdvertisements else { })
        (if runtimeIface ? advertise then runtimeIface.advertise else { })
      ];

      dhcp4Settings = mergeAttrs [
        (if serviceSettings ? dhcp4 then serviceSettings.dhcp4 else { })
        (if containerIface ? dhcp4 then containerIface.dhcp4 else { })
        (if runtimeIface ? dhcp4 then runtimeIface.dhcp4 else { })
      ];

      radvdSettings = mergeAttrs [
        (if serviceSettings ? radvd then serviceSettings.radvd else { })
        (if serviceSettings ? ra then serviceSettings.ra else { })
        (if serviceSettings ? ipv6Ra then serviceSettings.ipv6Ra else { })
        (if containerIface ? radvd then containerIface.radvd else { })
        (if containerIface ? ra then containerIface.ra else { })
        (if containerIface ? ipv6Ra then containerIface.ipv6Ra else { })
        (if runtimeIface ? radvd then runtimeIface.radvd else { })
        (if runtimeIface ? ra then runtimeIface.ra else { })
        (if runtimeIface ? ipv6Ra then runtimeIface.ipv6Ra else { })
      ];

      dhcp4EnabledRequested = boolField dhcp4Settings [ "enable" ] (
        defaultDhcp4Advertise && isLocalAdapter
      );
      radvdEnabledRequested = boolField radvdSettings [ "enable" ] (
        defaultRadvdAdvertise && isLocalAdapter
      );

      ipv4Address = ipv4AddressFromCIDR firstIPv4Cidr;

      dhcp4Subnet = stringField dhcp4Settings [ "subnet" "cidr" ] firstIPv4Cidr;
      dhcp4Pool = stringField dhcp4Settings [ "pool" ] (defaultIPv4Pool ipv4Address);
      dhcp4Router = stringField dhcp4Settings [ "router" "gateway" ] ipv4Address;
      dhcp4DnsServers = stringListField dhcp4Settings [ "dnsServers" "nameServers" ] (
        lib.optionals (dhcp4Router != null) [ dhcp4Router ]
      );
      dhcp4Domain = stringField dhcp4Settings [ "domain" "domainName" ] "lan.";

      radvdPrefixes = stringListField radvdSettings [ "prefixes" ] ipv6Cidrs;
      radvdRdnss = stringListField radvdSettings [ "rdnss" "dnsServers" ] (
        lib.optionals (firstIPv6Cidr != null) [ (ipv4AddressFromCIDR firstIPv6Cidr) ]
      );
      radvdDomain = stringField radvdSettings [ "domain" "dnssl" "domainName" ] "lan.";

      dhcp4Renderable =
        dhcp4EnabledRequested
        && interfaceName != null
        && dhcp4Subnet != null
        && dhcp4Pool != null
        && dhcp4Router != null
        && dhcp4DnsServers != [ ];

      radvdRenderable =
        radvdEnabledRequested && interfaceName != null && radvdPrefixes != [ ] && radvdRdnss != [ ];

      derivedDhcp4 = dhcp4Renderable && dhcp4Settings == { };
      derivedRadvd = radvdRenderable && radvdSettings == { };

      base = {
        inherit
          ifName
          interfaceName
          sourceKind
          isLocalAdapter
          derivedDhcp4
          derivedRadvd
          dhcp4EnabledRequested
          radvdEnabledRequested
          dhcp4Renderable
          radvdRenderable
          ;
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
    }
    // {
      warnings =
        lib.optionals (dhcp4EnabledRequested && !dhcp4Renderable) [
          "s88/ControlModule/access/lookup/advertisements.nix: container '${
            containerModel.containerName or (containerModel.unitName or "<unknown>")
          }' requested DHCPv4 advertisement on interface '${ifName}', but the rendered interface data is incomplete. Control plane should provide authoritative DHCP settings."
        ]
        ++ lib.optionals (radvdEnabledRequested && !radvdRenderable) [
          "s88/ControlModule/access/lookup/advertisements.nix: container '${
            containerModel.containerName or (containerModel.unitName or "<unknown>")
          }' requested IPv6 RA advertisement on interface '${ifName}', but the rendered interface data is incomplete. Control plane should provide authoritative IPv6 advertisement settings."
        ];
    }
  ) (sortedAttrNames containerInterfaces);

  dhcp4Raw = lib.filter (entry: entry ? dhcp4) interfaceEntries;
  dhcp4Scopes = builtins.genList (
    idx:
    let
      entry = builtins.elemAt dhcp4Raw idx;
    in
    entry.dhcp4
    // {
      subnetId = idx + 1;
    }
  ) (builtins.length dhcp4Raw);

  radvdScopes = map (entry: entry.radvd) (lib.filter (entry: entry ? radvd) interfaceEntries);

  derivedWarnings =
    let
      derivedDhcp4 = lib.filter (entry: entry.derivedDhcp4) interfaceEntries;
      derivedRadvd = lib.filter (entry: entry.derivedRadvd) interfaceEntries;
    in
    lib.optionals (derivedDhcp4 != [ ]) [
      "s88/ControlModule/access/lookup/advertisements.nix: DHCPv4 advertisement for container '${
        containerModel.containerName or (containerModel.unitName or "<unknown>")
      }' is currently derived from rendered interface addresses. Control plane should provide authoritative DHCP allocation data."
    ]
    ++ lib.optionals (derivedRadvd != [ ]) [
      "s88/ControlModule/access/lookup/advertisements.nix: IPv6 RA advertisement for container '${
        containerModel.containerName or (containerModel.unitName or "<unknown>")
      }' is currently derived from rendered interface addresses. Control plane should provide authoritative IPv6 advertisement data."
    ];

  warnings = lib.unique (derivedWarnings ++ lib.concatMap (entry: entry.warnings) interfaceEntries);
in
{
  inherit
    dhcp4Scopes
    radvdScopes
    warnings
    ;
}
