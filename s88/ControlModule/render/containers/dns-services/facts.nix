{ lib, renderedModel, forwardingIntent ? { } }:

let
  runtimeTarget =
    if renderedModel ? runtimeTarget && builtins.isAttrs renderedModel.runtimeTarget then
      renderedModel.runtimeTarget
    else
      { };

  dnsService =
    if
      runtimeTarget ? services && builtins.isAttrs runtimeTarget.services && runtimeTarget.services ? dns
    then
      runtimeTarget.services.dns
    else
      null;

  stringList = value:
    if builtins.isList value then lib.filter builtins.isString value else [ ];

  listenAddresses = lib.unique (
    [
      "127.0.0.1"
      "::1"
    ]
    ++ stringList (dnsService.listen or [ ])
  );

  allowFrom = lib.unique (
    [
      "127.0.0.0/8"
      "::1/128"
    ]
    ++ stringList (dnsService.allowFrom or [ ])
  );

  forwarders =
    if dnsService ? forwarders then
      stringList dnsService.forwarders
    else if dnsService ? upstreams then
      stringList dnsService.upstreams
    else
      [ ];

  interfaces =
    if renderedModel ? interfaces && builtins.isAttrs renderedModel.interfaces then
      renderedModel.interfaces
    else
      { };

  explicitDnsForwardPairs =
    lib.filter
      (pair:
        builtins.isAttrs pair
        && (pair.action or "accept") == "accept"
        && (pair.trafficType or null) == "dns"
        && builtins.isList (pair."in" or null))
      (forwardingIntent.normalizedExplicitForwardPairs or [ ]);

  hasExplicitDnsAllowFrom =
    ifName:
    builtins.any (pair: builtins.elem ifName (pair."in" or [ ])) explicitDnsForwardPairs;

  directEgressBlockedTenants =
    if dnsService ? directEgressBlockedTenants && builtins.isList dnsService.directEgressBlockedTenants then
      lib.filter builtins.isString dnsService.directEgressBlockedTenants
    else
      null;

  shouldBlockInterface =
    ifName: iface:
    let
      sourceKind = iface.sourceKind or "";
      tenant = iface.tenant or null;
    in
    if sourceKind == "wan" || sourceKind == "overlay" then
      false
    else if sourceKind == "tenant" && directEgressBlockedTenants != null then
      builtins.isString tenant && builtins.elem tenant directEgressBlockedTenants
    else
      true;
in
if !(builtins.isAttrs dnsService) then
  null
else
  rec {
    inherit dnsService listenAddresses allowFrom forwarders interfaces;
    listen4 = lib.filter (value: builtins.isString value && lib.hasInfix "." value) listenAddresses;
    listen6 = lib.filter (value: builtins.isString value && lib.hasInfix ":" value) listenAddresses;
    forwarder4 = lib.filter (value: builtins.isString value && lib.hasInfix "." value) forwarders;
    forwarder6 = lib.filter (value: builtins.isString value && lib.hasInfix ":" value) forwarders;
    hasMixedForwarders = forwarder4 != [ ] && forwarder6 != [ ];
    deniedResolverCidrs = stringList (dnsService.deniedResolverCidrs or [ ]);
    deniedResolverCidrs4 = lib.filter (value: builtins.isString value && lib.hasInfix "." value) deniedResolverCidrs;
    deniedResolverCidrs6 = lib.filter (value: builtins.isString value && lib.hasInfix ":" value) deniedResolverCidrs;
    localZones =
      lib.filter
        (zone: builtins.isAttrs zone && builtins.isString (zone.name or null) && zone.name != "")
        (if builtins.isList (dnsService.localZones or null) then dnsService.localZones else [ ]);
    localRecords =
      lib.filter
        (record: builtins.isAttrs record && builtins.isString (record.name or null) && record.name != "")
        (if builtins.isList (dnsService.localRecords or null) then dnsService.localRecords else [ ]);
    outgoingInterfaces = lib.unique (stringList (dnsService.outgoingInterfaces or [ ]));
    dnsEgressSources = if outgoingInterfaces != [ ] then outgoingInterfaces else listenAddresses;
    dnsEgressSources4 = lib.filter (value: builtins.isString value && lib.hasInfix "." value) dnsEgressSources;
    dnsEgressSources6 = lib.filter (value: builtins.isString value && lib.hasInfix ":" value) dnsEgressSources;
    ingressInterfaceNames =
      if dnsService.blockDirectEgress or false then
        lib.unique
          (
            lib.filter (name: name != "") (
              map
                (
                  ifName:
                  let
                    iface = interfaces.${ifName} or { };
                  in
                  if !(shouldBlockInterface ifName iface) then
                    ""
                  else if iface ? renderedIfName && builtins.isString iface.renderedIfName && iface.renderedIfName != "" then
                    if hasExplicitDnsAllowFrom iface.renderedIfName then "" else iface.renderedIfName
                  else if iface ? interfaceName && builtins.isString iface.interfaceName && iface.interfaceName != "" then
                    if hasExplicitDnsAllowFrom iface.interfaceName then "" else iface.interfaceName
                  else if hasExplicitDnsAllowFrom ifName then
                    ""
                  else
                    ifName
                )
                (builtins.attrNames interfaces)
            )
          )
      else
        [ ];
  }
