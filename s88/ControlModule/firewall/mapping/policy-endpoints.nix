{
  lib,
  interfaceView ? { },
  topology ? null,
  communicationContract ? { },
  ownership ? { },
  ...
}:

let
  sortedStrings =
    values:
    lib.sort builtins.lessThan (
      lib.unique (lib.filter (value: builtins.isString value && value != "") values)
    );

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

  fieldOr =
    attrs: name: fallback:
    if builtins.isAttrs attrs && builtins.hasAttr name attrs then attrs.${name} else fallback;

  fieldStrings =
    attrs: names: sortedStrings (lib.concatMap (name: asStringList (fieldOr attrs name null)) names);

  mergeAttrs =
    a: b:
    if builtins.isAttrs a && builtins.isAttrs b then
      a // b
    else if builtins.isAttrs a then
      a
    else if builtins.isAttrs b then
      b
    else
      { };

  isInterfaceLikeValue =
    value:
    builtins.isAttrs value
    && (
      value ? sourceKind
      || value ? sourceInterface
      || value ? backingRef
      || value ? routes
      || value ? renderedIfName
      || value ? runtimeIfName
      || value ? ifName
      || value ? desiredInterfaceName
      || value ? connectivity
      || value ? addr4
      || value ? addr6
      || value ? hostBridge
      || value ? renderedHostBridgeName
      || value ? iface
    );

  normalizeInterfaceEntry =
    fallbackName: value:
    let
      raw = if builtins.isAttrs value then value else { };
      nested = if raw ? iface && builtins.isAttrs raw.iface then raw.iface else raw;
      inferredName =
        if raw ? name && builtins.isString raw.name then
          raw.name
        else if raw ? runtimeIfName && builtins.isString raw.runtimeIfName then
          raw.runtimeIfName
        else if raw ? ifName && builtins.isString raw.ifName then
          raw.ifName
        else if raw ? renderedIfName && builtins.isString raw.renderedIfName then
          raw.renderedIfName
        else if raw ? sourceInterface && builtins.isString raw.sourceInterface then
          raw.sourceInterface
        else if nested ? name && builtins.isString nested.name then
          nested.name
        else if nested ? runtimeIfName && builtins.isString nested.runtimeIfName then
          nested.runtimeIfName
        else if nested ? ifName && builtins.isString nested.ifName then
          nested.ifName
        else if nested ? renderedIfName && builtins.isString nested.renderedIfName then
          nested.renderedIfName
        else if nested ? sourceInterface && builtins.isString nested.sourceInterface then
          nested.sourceInterface
        else
          fallbackName;
    in
    raw
    // {
      name = inferredName;
      iface = nested;
    };

  interfaceEntriesFromAttrset =
    attrs:
    map (name: normalizeInterfaceEntry name attrs.${name}) (
      lib.filter (name: isInterfaceLikeValue attrs.${name}) (builtins.attrNames attrs)
    );

  rawInterfaceViewEntries =
    if interfaceView != null && builtins.isAttrs interfaceView && interfaceView ? interfaceEntries then
      map (
        entry:
        if builtins.isAttrs entry && entry ? name && builtins.isString entry.name then
          normalizeInterfaceEntry entry.name entry
        else
          normalizeInterfaceEntry "" entry
      ) interfaceView.interfaceEntries
    else if
      interfaceView != null
      && builtins.isAttrs interfaceView
      && interfaceView ? interfaces
      && builtins.isAttrs interfaceView.interfaces
    then
      interfaceEntriesFromAttrset interfaceView.interfaces
    else if
      interfaceView != null
      && builtins.isAttrs interfaceView
      && interfaceView ? interfaceMap
      && builtins.isAttrs interfaceView.interfaceMap
    then
      interfaceEntriesFromAttrset interfaceView.interfaceMap
    else if
      interfaceView != null
      && builtins.isAttrs interfaceView
      && interfaceView ? ifaces
      && builtins.isAttrs interfaceView.ifaces
    then
      interfaceEntriesFromAttrset interfaceView.ifaces
    else if interfaceView != null && builtins.isAttrs interfaceView then
      interfaceEntriesFromAttrset interfaceView
    else
      [ ];

  topologyCandidateAttrs =
    let
      directCandidates = [
        (fieldOr topology "currentNode" null)
        (fieldOr topology "node" null)
        (fieldOr topology "current" null)
        (fieldOr topology "runtimeTarget" null)
        (fieldOr topology "currentRuntimeTarget" null)
        (fieldOr topology "target" null)
      ];

      nodesFromCurrentKey =
        if
          builtins.isAttrs topology
          && topology ? nodes
          && builtins.isAttrs topology.nodes
          && topology ? currentNodeKey
          && builtins.isString topology.currentNodeKey
          && builtins.hasAttr topology.currentNodeKey topology.nodes
        then
          [ topology.nodes.${topology.currentNodeKey} ]
        else
          [ ];

      nodesFromCurrentId =
        if
          builtins.isAttrs topology
          && topology ? nodes
          && builtins.isAttrs topology.nodes
          && topology ? currentNodeId
          && builtins.isString topology.currentNodeId
          && builtins.hasAttr topology.currentNodeId topology.nodes
        then
          [ topology.nodes.${topology.currentNodeId} ]
        else
          [ ];

      singletonNode =
        if
          builtins.isAttrs topology
          && topology ? nodes
          && builtins.isAttrs topology.nodes
          && builtins.length (builtins.attrNames topology.nodes) == 1
        then
          [ topology.nodes.${builtins.head (builtins.attrNames topology.nodes)} ]
        else
          [ ];
    in
    lib.filter builtins.isAttrs (
      directCandidates ++ nodesFromCurrentKey ++ nodesFromCurrentId ++ singletonNode
    );

  topologyMetadataEntries = lib.concatMap (
    candidate:
    if candidate ? interfaces && builtins.isAttrs candidate.interfaces then
      interfaceEntriesFromAttrset candidate.interfaces
    else
      interfaceEntriesFromAttrset candidate
  ) topologyCandidateAttrs;

  entryFieldOr =
    entry: name: fallback:
    if builtins.isAttrs entry && builtins.hasAttr name entry then
      entry.${name}
    else if entry ? iface && builtins.isAttrs entry.iface && builtins.hasAttr name entry.iface then
      entry.iface.${name}
    else
      fallback;

  backingRefOf =
    entry:
    let
      value = entryFieldOr entry "backingRef" { };
    in
    if builtins.isAttrs value then value else { };

  identityOf =
    entry:
    let
      value = entryFieldOr entry "identity" { };
    in
    if builtins.isAttrs value then value else { };

  sourceKindOf =
    entry:
    let
      direct = entryFieldOr entry "sourceKind" null;
    in
    if builtins.isString direct then direct else null;

  routeListOf =
    entry:
    let
      value = entryFieldOr entry "routes" null;
      ipv4 =
        if builtins.isAttrs value && value ? ipv4 && builtins.isList value.ipv4 then value.ipv4 else [ ];
      ipv6 =
        if builtins.isAttrs value && value ? ipv6 && builtins.isList value.ipv6 then value.ipv6 else [ ];
    in
    if builtins.isList value then value else ipv4 ++ ipv6;

  interfaceAliasesForEntry =
    entry:
    let
      backingRef = backingRefOf entry;
      identity = identityOf entry;
      connectivity =
        let
          value = entryFieldOr entry "connectivity" { };
        in
        if builtins.isAttrs value then value else { };
    in
    sortedStrings [
      entry.name
      (entryFieldOr entry "ifName" null)
      (entryFieldOr entry "renderedIfName" null)
      (entryFieldOr entry "runtimeIfName" null)
      (entryFieldOr entry "sourceInterface" null)
      (entryFieldOr entry "desiredInterfaceName" null)
      (entryFieldOr entry "hostInterfaceName" null)
      (entryFieldOr entry "containerInterfaceName" null)
      (entryFieldOr entry "assignedUplinkName" null)
      (entryFieldOr entry "renderedHostBridgeName" null)
      (entryFieldOr entry "hostBridge" null)
      (entryFieldOr entry "upstream" null)
      (if backingRef ? id && builtins.isString backingRef.id then backingRef.id else null)
      (if backingRef ? name && builtins.isString backingRef.name then backingRef.name else null)
      (if backingRef ? kind && builtins.isString backingRef.kind then backingRef.kind else null)
      (if identity ? portName && builtins.isString identity.portName then identity.portName else null)
      (
        if connectivity ? upstream && builtins.isString connectivity.upstream then
          connectivity.upstream
        else
          null
      )
    ];

  aliasesOverlap = left: right: lib.any (value: lib.elem value right) left;

  mergeInterfaceEntry =
    base: overlay:
    let
      mergedIface = mergeAttrs (fieldOr base "iface" { }) (fieldOr overlay "iface" { });
      merged = (mergeAttrs overlay base) // {
        iface = mergedIface;
        name = base.name;
      };
    in
    merged;

  enrichedInterfaceViewEntries = map (
    entry:
    let
      metadata = lib.findFirst (
        candidate: aliasesOverlap (interfaceAliasesForEntry entry) (interfaceAliasesForEntry candidate)
      ) null topologyMetadataEntries;
    in
    if metadata == null then entry else mergeInterfaceEntry entry metadata
  ) rawInterfaceViewEntries;

  interfaceEntries =
    if enrichedInterfaceViewEntries != [ ] then
      enrichedInterfaceViewEntries
    else
      topologyMetadataEntries;

  interfaceNamesForEntries = entries: sortedStrings (map (entry: entry.name) entries);

  routeHasDefault =
    route:
    builtins.isAttrs route
    && route ? dst
    && builtins.isString route.dst
    && (
      route.dst == "0.0.0.0/0"
      || route.dst == "::/0"
      || route.dst == "0000:0000:0000:0000:0000:0000:0000:0000/0"
    );

  entryHasDefaultRoute = entry: lib.any routeHasDefault (routeListOf entry);

  aliasMatchesEntry =
    alias: entry:
    let
      aliases = interfaceAliasesForEntry entry;
      aliasLen = builtins.stringLength alias;
    in
    builtins.isString alias
    && alias != ""
    && lib.any (
      candidate: candidate == alias || (aliasLen >= 3 && lib.hasInfix alias candidate)
    ) aliases;

  interfaceNamesMatchingAliases =
    aliases:
    interfaceNamesForEntries (
      lib.filter (entry: lib.any (alias: aliasMatchesEntry alias entry) aliases) interfaceEntries
    );

  allInterfaceNames = interfaceNamesForEntries interfaceEntries;

  wanNames =
    if interfaceView != null && builtins.isAttrs interfaceView && interfaceView ? wanNames then
      sortedStrings interfaceView.wanNames
    else
      interfaceNamesForEntries (
        lib.filter (
          entry:
          let
            sourceKind = sourceKindOf entry;
            connectivity =
              let
                value = entryFieldOr entry "connectivity" { };
              in
              if builtins.isAttrs value then value else { };
            upstream = entryFieldOr entry "upstream" (
              if connectivity ? upstream && builtins.isString connectivity.upstream then
                connectivity.upstream
              else
                null
            );
          in
          sourceKind == "wan" || upstream == "wan"
        ) interfaceEntries
      );

  p2pNames = interfaceNamesForEntries (
    lib.filter (entry: sourceKindOf entry == "p2p") interfaceEntries
  );

  localAdapterNames = interfaceNamesForEntries (
    lib.filter (
      entry:
      let
        sourceKind = sourceKindOf entry;
      in
      sourceKind != null && sourceKind != "wan" && sourceKind != "p2p"
    ) interfaceEntries
  );

  defaultRouteInterfaceNames = interfaceNamesForEntries (
    lib.filter entryHasDefaultRoute interfaceEntries
  );

  currentSite =
    if topology != null && builtins.isAttrs topology && topology ? currentSite then
      topology.currentSite
    else
      { };

  currentRoleName =
    if topology != null && builtins.isAttrs topology && topology ? currentRoleName then
      topology.currentRoleName
    else if
      topology != null
      && builtins.isAttrs topology
      && topology ? current
      && builtins.isAttrs topology.current
      && topology.current ? roleName
      && builtins.isString topology.current.roleName
    then
      topology.current.roleName
    else
      null;

  peerEntries =
    if
      topology != null
      && builtins.isAttrs topology
      && topology ? peerEntries
      && builtins.isList topology.peerEntries
    then
      lib.filter builtins.isAttrs topology.peerEntries
    else
      [ ];

  logicalNodeOf =
    target:
    if builtins.isAttrs target && target ? logicalNode && builtins.isAttrs target.logicalNode then
      target.logicalNode
    else
      { };

  runtimeTargetIdOf =
    target:
    if
      builtins.isAttrs target && target ? runtimeTargetId && builtins.isString target.runtimeTargetId
    then
      target.runtimeTargetId
    else if
      builtins.isAttrs target
      && target ? placement
      && builtins.isAttrs target.placement
      && target.placement ? runtimeTargetId
      && builtins.isString target.placement.runtimeTargetId
    then
      target.placement.runtimeTargetId
    else
      null;

  aliasesForPeerEntry =
    entry:
    let
      runtimeTarget =
        if entry ? runtimeTarget && builtins.isAttrs entry.runtimeTarget then entry.runtimeTarget else { };
      logicalNode = logicalNodeOf runtimeTarget;
    in
    sortedStrings [
      (if entry ? unitKey && builtins.isString entry.unitKey then entry.unitKey else null)
      (if entry ? rawUnitKey && builtins.isString entry.rawUnitKey then entry.rawUnitKey else null)
      (runtimeTargetIdOf runtimeTarget)
      (if logicalNode ? name && builtins.isString logicalNode.name then logicalNode.name else null)
      (if logicalNode ? site && builtins.isString logicalNode.site then logicalNode.site else null)
      (
        if logicalNode ? enterprise && builtins.isString logicalNode.enterprise then
          logicalNode.enterprise
        else
          null
      )
    ];

  peerUnitAliases =
    unitNames:
    sortedStrings (
      lib.concatMap (
        unitName:
        let
          matchedEntries = lib.filter (
            entry:
            lib.any (
              alias: alias == unitName || (builtins.stringLength unitName >= 3 && lib.hasInfix unitName alias)
            ) (aliasesForPeerEntry entry)
          ) peerEntries;
        in
        [ unitName ] ++ (lib.concatMap aliasesForPeerEntry matchedEntries)
      ) unitNames
    );

  interfaceNamesForPeerUnits = unitNames: interfaceNamesMatchingAliases (peerUnitAliases unitNames);

  tenantPrefixOwners =
    if currentSite ? tenantPrefixOwners && builtins.isAttrs currentSite.tenantPrefixOwners then
      currentSite.tenantPrefixOwners
    else
      { };

  tenantOwnerUnits =
    tenantName:
    sortedStrings (
      map (value: value.owner) (
        lib.filter (
          value:
          builtins.isAttrs value
          && value ? owner
          && builtins.isString value.owner
          && ((value ? netName && value.netName == tenantName) || (value ? name && value.name == tenantName))
        ) (lib.attrValues tenantPrefixOwners)
      )
    );

  ownershipEndpoints =
    if ownership ? endpoints && builtins.isList ownership.endpoints then
      lib.filter builtins.isAttrs ownership.endpoints
    else
      [ ];

  ownershipPrefixes =
    if ownership ? prefixes && builtins.isList ownership.prefixes then
      lib.filter builtins.isAttrs ownership.prefixes
    else
      [ ];

  tenantNamesForHost =
    hostName:
    sortedStrings (
      map (endpoint: endpoint.tenant) (
        lib.filter (
          endpoint:
          (endpoint.kind or null) == "host"
          && (endpoint.name or null) == hostName
          && endpoint ? tenant
          && builtins.isString endpoint.tenant
        ) ownershipEndpoints
      )
    );

  serviceDefinitions =
    if communicationContract ? services && builtins.isList communicationContract.services then
      lib.filter builtins.isAttrs communicationContract.services
    else
      [ ];

  providersForService =
    serviceName:
    let
      matchedServices = lib.filter (service: (service.name or null) == serviceName) serviceDefinitions;
    in
    sortedStrings (
      lib.concatMap (
        service:
        if service ? providers && builtins.isList service.providers then
          lib.filter builtins.isString service.providers
        else
          [ ]
      ) matchedServices
    );

  interfaceTags =
    if
      communicationContract ? interfaceTags && builtins.isAttrs communicationContract.interfaceTags
    then
      communicationContract.interfaceTags
    else
      { };

  interfaceTagKeys = builtins.attrNames interfaceTags;

  reverseTagKeysForValue =
    value:
    sortedStrings (
      lib.filter (
        key: builtins.isString interfaceTags.${key} && interfaceTags.${key} == value
      ) interfaceTagKeys
    );

  currentSiteUpstreamSelectorUnits = sortedStrings (
    asStringList (fieldOr currentSite "upstreamSelectorNodeName" null)
    ++ fieldStrings currentSite [ "upstreamSelectorNodeNames" ]
  );

  currentSiteCoreUnits = sortedStrings (
    asStringList (fieldOr currentSite "coreNodeName" null)
    ++ fieldStrings currentSite [ "coreNodeNames" ]
  );

  currentSiteTenantNames = sortedStrings (
    (map (tenant: tenant.name) (
      lib.filter (tenant: builtins.isAttrs tenant && tenant ? name && builtins.isString tenant.name) (
        if
          currentSite ? domains
          && builtins.isAttrs currentSite.domains
          && currentSite.domains ? tenants
          && builtins.isList currentSite.domains.tenants
        then
          currentSite.domains.tenants
        else
          [ ]
      )
    ))
    ++ (map (prefix: prefix.name) (
      lib.filter (
        prefix:
        builtins.isAttrs prefix
        && (prefix.kind or null) == "tenant"
        && prefix ? name
        && builtins.isString prefix.name
      ) ownershipPrefixes
    ))
  );

  currentSiteTenantUnits = sortedStrings (lib.concatMap tenantOwnerUnits currentSiteTenantNames);

  tenantTransitNames = interfaceNamesForPeerUnits currentSiteTenantUnits;

  localInternalNames = if localAdapterNames != [ ] then localAdapterNames else tenantTransitNames;

  upstreamFacingNames = sortedStrings (
    wanNames
    ++ defaultRouteInterfaceNames
    ++ interfaceNamesForPeerUnits currentSiteUpstreamSelectorUnits
    ++ interfaceNamesForPeerUnits currentSiteCoreUnits
    ++ interfaceNamesMatchingAliases [
      "upstream"
      "wan"
      "external-wan"
    ]
  );

  managementTenantName =
    if lib.elem "mgmt" currentSiteTenantNames then
      "mgmt"
    else if lib.elem "management" currentSiteTenantNames then
      "management"
    else
      null;

  resolveTenantName =
    tenantName:
    let
      ownerUnits = tenantOwnerUnits tenantName;
      fromOwners = interfaceNamesForPeerUnits ownerUnits;
      fromAliases = interfaceNamesMatchingAliases [
        tenantName
        "tenant-${tenantName}"
        "access-${tenantName}"
        "transit-${tenantName}"
      ];
    in
    sortedStrings (fromOwners ++ fromAliases);

  resolveHostName =
    hostName:
    let
      tenantNames = tenantNamesForHost hostName;
      direct = interfaceNamesMatchingAliases [ hostName ];
    in
    sortedStrings (direct ++ (lib.concatMap resolveTenantName tenantNames));

  resolveExternalName =
    externalName:
    let
      direct = interfaceNamesMatchingAliases [
        externalName
        "external-${externalName}"
      ];
    in
    if externalName == "wan" then sortedStrings (direct ++ upstreamFacingNames) else direct;

  resolveTagKey =
    key:
    if lib.hasPrefix "tenant-" key then
      resolveTenantName (builtins.substring 7 (builtins.stringLength key - 7) key)
    else if lib.hasPrefix "service-" key then
      let
        direct = interfaceNamesMatchingAliases [ key ];
      in
      if managementTenantName != null then
        sortedStrings (direct ++ resolveTenantName managementTenantName)
      else
        direct
    else if lib.hasPrefix "external-" key then
      resolveExternalName (builtins.substring 9 (builtins.stringLength key - 9) key)
    else if lib.hasPrefix "wan-" key then
      sortedStrings (interfaceNamesMatchingAliases [ key ] ++ resolveExternalName "wan")
    else
      interfaceNamesMatchingAliases [ key ];

  resolveTagValue = value: sortedStrings (lib.concatMap resolveTagKey (reverseTagKeysForValue value));

  resolveServiceName =
    serviceName:
    let
      providers = providersForService serviceName;
      direct = interfaceNamesMatchingAliases [
        serviceName
        "service-${serviceName}"
      ];
      fromProviders = lib.concatMap resolveHostName providers;
      fromTags = resolveTagValue serviceName;
      fallback =
        if providers == [ ] && fromTags == [ ] && managementTenantName != null then
          resolveTenantName managementTenantName
        else
          [ ];
    in
    sortedStrings (direct ++ fromProviders ++ fromTags ++ fallback);

  resolveKindedSpec =
    spec:
    let
      kind = fieldOr spec "kind" null;
      name = fieldOr spec "name" null;
      members = fieldStrings spec [ "members" ];
      uplinks = fieldStrings spec [
        "uplink"
        "uplinks"
      ];
    in
    if kind == "tenant" && builtins.isString name then
      resolveTenantName name
    else if kind == "tenant-set" then
      sortedStrings (lib.concatMap resolveTenantName members)
    else if kind == "service" && builtins.isString name then
      resolveServiceName name
    else if kind == "external" then
      sortedStrings (
        (if builtins.isString name then resolveExternalName name else [ ])
        ++ (lib.concatMap resolveExternalName uplinks)
      )
    else if kind == "host" && builtins.isString name then
      resolveHostName name
    else
      [ ];

  resolveKeyword =
    name:
    if name == "any" || name == "all" || name == "anywhere" then
      allInterfaceNames
    else if
      name == "wan" || name == "external" || name == "upstream" || name == "uplink" || name == "uplinks"
    then
      upstreamFacingNames
    else if name == "p2p" || name == "transit" || name == "fabric" then
      p2pNames
    else if name == "local" || name == "lan" || name == "internal" then
      localInternalNames
    else if name == "tenant" || name == "tenants" then
      tenantTransitNames
    else if currentRoleName != null && name == currentRoleName then
      localInternalNames
    else
      [ ];

  resolveString =
    name:
    let
      keywordResolved = resolveKeyword name;
      direct = interfaceNamesMatchingAliases [ name ];

      byPrefix =
        if lib.hasPrefix "tenant-" name then
          resolveTenantName (builtins.substring 7 (builtins.stringLength name - 7) name)
        else if lib.hasPrefix "service-" name then
          resolveServiceName (builtins.substring 8 (builtins.stringLength name - 8) name)
        else if lib.hasPrefix "external-" name then
          resolveExternalName (builtins.substring 9 (builtins.stringLength name - 9) name)
        else
          [ ];

      bySemanticName =
        resolveTenantName name
        ++ resolveServiceName name
        ++ resolveHostName name
        ++ resolveExternalName name;

      byReverseTag = resolveTagValue name;
    in
    sortedStrings (keywordResolved ++ direct ++ byPrefix ++ bySemanticName ++ byReverseTag);

  selectorFieldNames = [
    "selector"
    "selectors"
    "endpoint"
    "endpoints"
    "interface"
    "interfaces"
    "ifName"
    "ifNames"
    "name"
    "names"
    "sourceInterface"
    "sourceInterfaces"
    "uplink"
    "uplinks"
  ];

  resolveEndpoint =
    spec:
    if spec == null then
      [ ]
    else if builtins.isString spec then
      resolveString spec
    else if builtins.isList spec then
      sortedStrings (lib.concatMap resolveEndpoint spec)
    else if builtins.isAttrs spec then
      let
        kindResolved = resolveKindedSpec spec;
        selectorValues = fieldStrings spec selectorFieldNames;
        selectorResolved = lib.concatMap resolveString selectorValues;
      in
      sortedStrings (kindResolved ++ selectorResolved)
    else
      [ ];
in
{
  inherit
    resolveEndpoint
    allInterfaceNames
    wanNames
    p2pNames
    localAdapterNames
    ;
}
