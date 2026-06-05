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

  asList =
    value:
    if value == null then
      [ ]
    else if builtins.isList value then
      value
    else
      [ value ];

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

  explicitDnsServiceEgressPairs =
    lib.filter
      (pair:
        builtins.isAttrs pair
        && (pair.action or "accept") == "accept"
        && (pair.trafficType or null) == "dns"
        && builtins.isList (pair."in" or null)
        && builtins.isList (pair."out" or null)
        && builtins.isList (pair.sourcePrefixes or null)
        && pair.sourcePrefixes != [ ])
      (forwardingIntent.normalizedExplicitForwardPairs or [ ]);

  sourcePrefixRecord = value:
    let
      prefix =
        if builtins.isString value then
          value
        else if builtins.isAttrs value && builtins.isString (value.prefix or null) then
          value.prefix
        else
          "";
      family =
        if builtins.isAttrs value && (value.family or null) == 6 then
          6
        else if builtins.isString prefix && lib.hasInfix ":" prefix then
          6
        else
          4;
    in
    if prefix == "" then null else { inherit prefix family; };

  dnsServiceForwardEgressRules =
    lib.concatMap
      (pair:
        lib.concatMap
          (source:
            lib.concatMap
              (inIf:
                map
                  (outIf: {
                    inherit source;
                    inInterface = inIf;
                    outInterface = outIf;
                  })
                  (stringList (pair."out" or [ ])))
              (stringList (pair."in" or [ ])))
          (lib.filter (value: value != null) (map sourcePrefixRecord (asList (pair.sourcePrefixes or [ ])))))
      explicitDnsServiceEgressPairs;

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
    else if directEgressBlockedTenants != null then
      sourceKind == "tenant" && builtins.isString tenant && builtins.elem tenant directEgressBlockedTenants
    else
      true;
in
if !(builtins.isAttrs dnsService) then
  null
else
  rec {
    inherit dnsService listenAddresses allowFrom forwarders interfaces dnsServiceForwardEgressRules;
    listen4 = lib.filter (value: builtins.isString value && lib.hasInfix "." value) listenAddresses;
    listen6 = lib.filter (value: builtins.isString value && lib.hasInfix ":" value) listenAddresses;
    forwarder4 = lib.filter (value: builtins.isString value && lib.hasInfix "." value) forwarders;
    forwarder6 = lib.filter (value: builtins.isString value && lib.hasInfix ":" value) forwarders;
    hasMixedForwarders = forwarder4 != [ ] && forwarder6 != [ ];
    deniedResolverCidrs = stringList (dnsService.deniedResolverCidrs or [ ]);
    deniedResolverCidrs4 = lib.filter (value: builtins.isString value && lib.hasInfix "." value) deniedResolverCidrs;
    deniedResolverCidrs6 = lib.filter (value: builtins.isString value && lib.hasInfix ":" value) deniedResolverCidrs;
    publicResolverForwardIngressNames =
      if ((dnsService.killSwitch or { }).blockPublicResolvers or false) then
        lib.unique
          (
            lib.filter (name: name != "") (
              map
                (
                  ifName:
                  let
                    iface = interfaces.${ifName} or { };
                    sourceKind = iface.sourceKind or "";
                    renderedName =
                      if iface ? renderedIfName && builtins.isString iface.renderedIfName && iface.renderedIfName != "" then
                        iface.renderedIfName
                      else if iface ? interfaceName && builtins.isString iface.interfaceName && iface.interfaceName != "" then
                        iface.interfaceName
                      else
                        ifName;
                  in
                  if sourceKind == "wan" || sourceKind == "overlay" then "" else renderedName
                )
                (builtins.attrNames interfaces)
            )
          )
      else
        [ ];
    localZones =
      lib.filter
        (zone: builtins.isAttrs zone && builtins.isString (zone.name or null) && zone.name != "")
        (if builtins.isList (dnsService.localZones or null) then dnsService.localZones else [ ]);
    localRecords =
      lib.filter
        (record: builtins.isAttrs record && builtins.isString (record.name or null) && record.name != "")
        (if builtins.isList (dnsService.localRecords or null) then dnsService.localRecords else [ ]);
  namespaceFallback =
    if builtins.isAttrs (dnsService.namespaceFallback or null) then dnsService.namespaceFallback else { };
  namespaceFallbackDecisionsRaw =
    if builtins.isList (namespaceFallback.decisions or null) then namespaceFallback.decisions else [ ];
  invalidNamespaceConflictDecisions =
    lib.filter
      (decision:
        builtins.isAttrs decision
        && !(decision.publicRecursionFallback or false)
        && builtins.elem (decision.action or null) [ "block" "deny" ]
        && !(
          builtins.isString (decision.requesterScope or null)
          && decision.requesterScope != ""
          && builtins.isString (decision.namespace or null)
          && decision.namespace != ""
        ))
      namespaceFallbackDecisionsRaw;
  namespaceFallbackDecisions =
      if invalidNamespaceConflictDecisions != [ ] then
        let
          bad = builtins.head invalidNamespaceConflictDecisions;
          badNamespace =
            if builtins.isString (bad.namespace or null) && bad.namespace != "" then
              bad.namespace
            else
              "<missing-namespace>";
          badAction =
            if builtins.isString (bad.action or null) && bad.action != "" then
              bad.action
            else
              "<missing-action>";
        in
        throw "NixOS DNS renderer requires requesterScope and namespace for modeled namespace-conflict state predicate action '${badAction}' on '${badNamespace}'"
      else
      lib.filter
        (decision:
          builtins.isAttrs decision
          && builtins.isString (decision.requesterScope or null)
          && decision.requesterScope != ""
          && builtins.isString (decision.namespace or null)
          && decision.namespace != ""
          && !((decision.publicRecursionFallback or false))
          && builtins.elem (decision.action or null) [ "block" "deny" ])
        namespaceFallbackDecisionsRaw;
    dnsRoles = if builtins.isAttrs (dnsService.roles or null) then dnsService.roles else { };
    recursionRole = if builtins.isAttrs (dnsRoles.recursion or null) then dnsRoles.recursion else { };
    roleOutgoingInterfaces = stringList (recursionRole.outgoingInterfaces or [ ]);
    outgoingInterfaces = lib.unique (if roleOutgoingInterfaces != [ ] then roleOutgoingInterfaces else stringList (dnsService.outgoingInterfaces or [ ]));
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
