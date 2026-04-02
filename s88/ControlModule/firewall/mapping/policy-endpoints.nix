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

  ifaceOf =
    entry:
    if builtins.isAttrs entry && entry ? iface && builtins.isAttrs entry.iface then
      entry.iface
    else if builtins.isAttrs entry then
      entry
    else
      { };

  entryFieldOr =
    entry: name: fallback:
    if builtins.isAttrs entry && builtins.hasAttr name entry then
      entry.${name}
    else
      let
        iface = ifaceOf entry;
      in
      if builtins.isAttrs iface && builtins.hasAttr name iface then iface.${name} else fallback;

  topologyCurrent =
    if
      topology != null
      && builtins.isAttrs topology
      && topology ? current
      && builtins.isAttrs topology.current
    then
      topology.current
    else
      { };

  currentSite =
    if
      topology != null
      && builtins.isAttrs topology
      && topology ? currentSite
      && builtins.isAttrs topology.currentSite
    then
      topology.currentSite
    else if topologyCurrent ? site && builtins.isAttrs topologyCurrent.site then
      topologyCurrent.site
    else
      { };

  rawInterfaceEntries =
    if interfaceView != null && builtins.isAttrs interfaceView && interfaceView ? interfaceEntries then
      lib.filter builtins.isAttrs interfaceView.interfaceEntries
    else
      [ ];

  interfaceEntries = lib.filter (
    entry: entry ? name && builtins.isString entry.name && entry.name != ""
  ) rawInterfaceEntries;

  sourceKindOf =
    entry:
    let
      sourceKind = entryFieldOr entry "sourceKind" null;
    in
    if builtins.isString sourceKind then sourceKind else null;

  interfaceRefStrings =
    entry:
    let
      backingRef = entryFieldOr entry "backingRef" { };
    in
    sortedStrings [
      (entry.name or null)
      (entryFieldOr entry "sourceInterface" null)
      (entryFieldOr entry "runtimeIfName" null)
      (entryFieldOr entry "renderedIfName" null)
      (entryFieldOr entry "ifName" null)
      (entryFieldOr entry "containerInterfaceName" null)
      (entryFieldOr entry "hostInterfaceName" null)
      (entryFieldOr entry "desiredInterfaceName" null)
      (entryFieldOr entry "assignedUplinkName" null)
      (entryFieldOr entry "upstream" null)
      (if builtins.isAttrs backingRef then backingRef.name or null else null)
      (if builtins.isAttrs backingRef then backingRef.id or null else null)
      (if builtins.isAttrs backingRef then backingRef.kind or null else null)
    ];

  matchInterfaceEntriesByToken =
    token:
    lib.filter (
      entry: lib.any (ref: ref == token || lib.hasInfix token ref) (interfaceRefStrings entry)
    ) interfaceEntries;

  tenantAttachments =
    if currentSite ? attachments && builtins.isList currentSite.attachments then
      lib.filter (
        attachment:
        builtins.isAttrs attachment
        && (attachment.kind or null) == "tenant"
        && attachment ? name
        && builtins.isString attachment.name
        && attachment ? unit
        && builtins.isString attachment.unit
      ) currentSite.attachments
    else
      [ ];

  tenantInterfaceByName = builtins.listToAttrs (
    lib.filter (entry: entry != null) (
      map (
        attachment:
        let
          candidateEntries = matchInterfaceEntriesByToken attachment.unit;
          selectedIfName =
            if builtins.length candidateEntries > 0 then (builtins.head candidateEntries).name else null;
        in
        if selectedIfName != null then
          {
            name = attachment.name;
            value = selectedIfName;
          }
        else
          null
      ) tenantAttachments
    )
  );

  upstreamSelectorNodeName =
    if
      currentSite ? upstreamSelectorNodeName
      && builtins.isString currentSite.upstreamSelectorNodeName
      && currentSite.upstreamSelectorNodeName != ""
    then
      currentSite.upstreamSelectorNodeName
    else
      "s-router-upstream-selector";

  upstreamInterfaceCandidates = lib.filter (
    entry:
    lib.any (ref: lib.hasInfix upstreamSelectorNodeName ref || ref == "upstream") (
      interfaceRefStrings entry
    )
    || sourceKindOf entry == "wan"
  ) interfaceEntries;

  explicitWanNames =
    if interfaceView != null && builtins.isAttrs interfaceView && interfaceView ? wanNames then
      sortedStrings interfaceView.wanNames
    else
      [ ];

  upstreamInterfaceName =
    if builtins.length upstreamInterfaceCandidates > 0 then
      (builtins.head upstreamInterfaceCandidates).name
    else if explicitWanNames != [ ] then
      builtins.head explicitWanNames
    else
      null;

  ownershipEndpoints =
    if ownership ? endpoints && builtins.isList ownership.endpoints then
      lib.filter (
        endpoint:
        builtins.isAttrs endpoint
        && endpoint ? name
        && builtins.isString endpoint.name
        && endpoint ? tenant
        && builtins.isString endpoint.tenant
      ) ownership.endpoints
    else
      [ ];

  serviceDefinitions =
    if communicationContract ? services && builtins.isList communicationContract.services then
      lib.filter (
        service: builtins.isAttrs service && service ? name && builtins.isString service.name
      ) communicationContract.services
    else
      [ ];

  providerTenantFor =
    providerName:
    let
      matches = lib.filter (endpoint: endpoint.name == providerName) ownershipEndpoints;
    in
    if builtins.length matches > 0 then (builtins.head matches).tenant else null;

  serviceInterfacesByName = builtins.listToAttrs (
    map (
      service:
      let
        providers =
          if service ? providers && builtins.isList service.providers then
            lib.filter builtins.isString service.providers
          else
            [ ];

        providerTenants = lib.filter (tenant: tenant != null) (map providerTenantFor providers);

        interfaces = sortedStrings (
          lib.filter (iface: iface != null) (
            map (
              tenant:
              if builtins.hasAttr tenant tenantInterfaceByName then tenantInterfaceByName.${tenant} else null
            ) providerTenants
          )
        );
      in
      {
        name = service.name;
        value = interfaces;
      }
    ) serviceDefinitions
  );

  interfaceTags =
    if
      communicationContract ? interfaceTags && builtins.isAttrs communicationContract.interfaceTags
    then
      communicationContract.interfaceTags
    else
      { };

  normalizeToken =
    token:
    if builtins.hasAttr token interfaceTags && builtins.isString interfaceTags.${token} then
      interfaceTags.${token}
    else
      token;

  allKnownInterfaces = sortedStrings (
    (builtins.attrValues tenantInterfaceByName)
    ++ lib.optionals (upstreamInterfaceName != null) [ upstreamInterfaceName ]
  );

  resolveStringEndpoint =
    endpoint:
    let
      token = normalizeToken endpoint;
    in
    if token == "any" then
      allKnownInterfaces
    else if token == "wan" || token == "external-wan" || token == "upstream" then
      lib.optionals (upstreamInterfaceName != null) [ upstreamInterfaceName ]
    else if builtins.hasAttr token tenantInterfaceByName then
      [ tenantInterfaceByName.${token} ]
    else if builtins.hasAttr token serviceInterfacesByName then
      serviceInterfacesByName.${token}
    else
      [ ];

  resolveAttrEndpoint =
    endpoint:
    let
      kind = endpoint.kind or null;
    in
    if kind == "tenant" && endpoint ? name && builtins.hasAttr endpoint.name tenantInterfaceByName then
      [ tenantInterfaceByName.${endpoint.name} ]
    else if kind == "tenant-set" && endpoint ? members && builtins.isList endpoint.members then
      sortedStrings (
        lib.concatMap (
          member:
          if builtins.isString member && builtins.hasAttr member tenantInterfaceByName then
            [ tenantInterfaceByName.${member} ]
          else
            [ ]
        ) endpoint.members
      )
    else if
      kind == "external"
      && (
        (endpoint.name or null) == "wan"
        || (endpoint.name or null) == "external-wan"
        || (endpoint.name or null) == "upstream"
      )
    then
      lib.optionals (upstreamInterfaceName != null) [ upstreamInterfaceName ]
    else if
      kind == "service" && endpoint ? name && builtins.hasAttr endpoint.name serviceInterfacesByName
    then
      serviceInterfacesByName.${endpoint.name}
    else
      let
        selectorValues = sortedStrings (
          lib.concatMap (field: asStringList (fieldOr endpoint field null)) [
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
          ]
        );
      in
      sortedStrings (lib.concatMap resolveStringEndpoint selectorValues);

  resolveEndpoint =
    endpoint:
    if endpoint == null then
      [ ]
    else if endpoint == "any" then
      allKnownInterfaces
    else if builtins.isString endpoint then
      resolveStringEndpoint endpoint
    else if builtins.isList endpoint then
      sortedStrings (lib.concatMap resolveEndpoint endpoint)
    else if builtins.isAttrs endpoint then
      resolveAttrEndpoint endpoint
    else
      [ ];

  wanNames = explicitWanNames;

  p2pNames = sortedStrings (
    map (entry: entry.name) (lib.filter (entry: sourceKindOf entry == "p2p") interfaceEntries)
  );

  localAdapterNames = sortedStrings (
    map (entry: entry.name) (
      lib.filter (
        entry:
        let
          sourceKind = sourceKindOf entry;
        in
        sourceKind != "wan" && sourceKind != "p2p"
      ) interfaceEntries
    )
  );
in
{
  inherit
    resolveEndpoint
    allKnownInterfaces
    wanNames
    p2pNames
    localAdapterNames
    ;
}
