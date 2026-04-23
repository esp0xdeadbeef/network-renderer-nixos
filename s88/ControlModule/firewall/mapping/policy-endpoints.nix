{
  lib,
  interfaceView ? { },
  currentSite ? { },
  communicationContract ? { },
  ownership ? { },
  runtimeTarget ? { },
  roleName ? null,
  unitName ? null,
  containerName ? null,
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

  lastStringSegment =
    separator: value:
    let
      parts = lib.splitString separator value;
      count = builtins.length parts;
    in
    if count == 0 then null else builtins.elemAt parts (count - 1);

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

  rawInterfaceEntries =
    if interfaceView != null && builtins.isAttrs interfaceView && interfaceView ? interfaceEntries then
      lib.filter builtins.isAttrs interfaceView.interfaceEntries
    else
      [ ];

  interfaceEntries = lib.filter (
    entry: entry ? name && builtins.isString entry.name && entry.name != ""
  ) rawInterfaceEntries;

  semanticInterfaceOf =
    entry:
    let
      semanticInterface = entryFieldOr entry "semanticInterface" null;
      semantic = entryFieldOr entry "semantic" null;
    in
    if builtins.isAttrs semanticInterface then
      semanticInterface
    else if builtins.isAttrs semantic then
      semantic
    else
      { };

  sourceKindOf =
    entry:
    let
      semanticInterface = semanticInterfaceOf entry;
      sourceKind = entryFieldOr entry "sourceKind" null;
    in
    if semanticInterface ? kind && builtins.isString semanticInterface.kind then
      semanticInterface.kind
    else if builtins.isString sourceKind then
      sourceKind
    else
      null;

  interfaceRefStrings =
    entry:
    let
      backingRef = entryFieldOr entry "backingRef" { };
    in
    sortedStrings [
      (entry.name or null)
      (entry.key or null)
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
      (
        if builtins.isAttrs backingRef && backingRef ? id && builtins.isString backingRef.id then
          lastStringSegment "::" backingRef.id
        else
          null
      )
      (if builtins.isAttrs backingRef then backingRef.kind or null else null)
    ];

  interfaceNameForLink =
    linkName:
    let
      matches = sortedStrings (
        map (entry: entry.name) (
          lib.filter (entry: builtins.elem linkName (interfaceRefStrings entry)) interfaceEntries
        )
      );
    in
    if matches == [ ] then
      null
    else if builtins.length matches == 1 then
      builtins.head matches
    else
      throw ''
        s88/ControlModule/firewall/mapping/policy-endpoints.nix: link '${linkName}' matched multiple rendered interfaces

        matches:
        ${builtins.toJSON matches}
      '';

  currentSiteNodes =
    if currentSite ? nodes && builtins.isAttrs currentSite.nodes then currentSite.nodes else { };

  runtimeLogicalNodeName =
    if
      runtimeTarget ? interfaces
      && builtins.isAttrs runtimeTarget.interfaces
      && runtimeTarget.interfaces != { }
    then
      let
        names = sortedStrings (
          map (
            ifName:
            let
              iface = runtimeTarget.interfaces.${ifName};
            in
            if iface ? logicalNode && builtins.isString iface.logicalNode then iface.logicalNode else null
          ) (builtins.attrNames runtimeTarget.interfaces)
        );
      in
      if builtins.length names == 1 then builtins.head names else null
    else
      null;

  currentNodeName =
    if currentSite ? policyNodeName && builtins.isString currentSite.policyNodeName then
      currentSite.policyNodeName
    else if runtimeLogicalNodeName != null then
      runtimeLogicalNodeName
    else
      let
        names = sortedStrings (map (entry: entryFieldOr entry "logicalNode" null) interfaceEntries);
      in
      if builtins.length names == 1 then builtins.head names else null;

  currentNode =
    if
      builtins.hasAttr currentNodeName currentSiteNodes
      && builtins.isAttrs currentSiteNodes.${currentNodeName}
    then
      currentSiteNodes.${currentNodeName}
    else
      { };

  currentNodeInterfaces =
    if currentNode ? interfaces && builtins.isAttrs currentNode.interfaces then
      currentNode.interfaces
    else
      { };

  transitAdjacencies =
    if
      currentSite ? transit
      && builtins.isAttrs currentSite.transit
      && currentSite.transit ? adjacencies
      && builtins.isList currentSite.transit.adjacencies
    then
      lib.filter builtins.isAttrs currentSite.transit.adjacencies
    else
      [ ];

  adjacencyUnits =
    adjacency:
    sortedStrings (
      map
        (
          endpoint:
          if builtins.isAttrs endpoint && endpoint ? unit && builtins.isString endpoint.unit then
            endpoint.unit
          else
            null
        )
        (if adjacency ? endpoints && builtins.isList adjacency.endpoints then adjacency.endpoints else [ ])
    );

  adjacencyLinkName =
    adjacency:
    if adjacency ? link && builtins.isString adjacency.link then
      adjacency.link
    else if adjacency ? name && builtins.isString adjacency.name then
      adjacency.name
    else if adjacency ? id && builtins.isString adjacency.id then
      lastStringSegment "::" adjacency.id
    else
      null;

  adjacencyForPair =
    {
      a,
      b,

      linkNameMatches ? null,
    }:
    let
      matches = lib.filter (
        adjacency:
        let
          units = adjacencyUnits adjacency;
        in
        builtins.length units == 2 && builtins.elem a units && builtins.elem b units
      ) transitAdjacencies;

      matchesByLink =
        if linkNameMatches == null then
          [ ]
        else
          lib.filter (
            adjacency:
            let
              ln = adjacencyLinkName adjacency;
            in
            ln != null && linkNameMatches ln
          ) matches;

      chosen =
        if builtins.length matchesByLink == 1 then
          builtins.head matchesByLink
        else if builtins.length matchesByLink > 1 then
          throw ''
            s88/ControlModule/firewall/mapping/policy-endpoints.nix: lane selector matched multiple transit adjacencies for '${a}' and '${b}'

            matches:
            ${builtins.toJSON (map adjacencyLinkName matchesByLink)}
          ''
        else if builtins.length matches == 1 then
          builtins.head matches
        else if matches == [ ] then
          null
        else
          throw ''
            s88/ControlModule/firewall/mapping/policy-endpoints.nix: multiple transit adjacencies matched '${a}' and '${b}'

            matches:
            ${builtins.toJSON (map adjacencyLinkName matches)}
          '';
    in
    chosen;

  transitEdges = lib.concatMap (
    adjacency:
    let
      units = adjacencyUnits adjacency;
    in
    if builtins.length units == 2 then
      let
        a = builtins.elemAt units 0;
        b = builtins.elemAt units 1;
      in
      [
        {
          from = a;
          to = b;
        }
        {
          from = b;
          to = a;
        }
      ]
    else
      [ ]
  ) transitAdjacencies;

  neighborsOf =
    unit: sortedStrings (map (edge: edge.to) (lib.filter (edge: edge.from == unit) transitEdges));

  lastElem =
    list:
    let
      n = builtins.length list;
    in
    if n == 0 then null else builtins.elemAt list (n - 1);

  findPath =
    {
      start,
      goal,
    }:
    let
      go =
        visited: frontier:
        if frontier == [ ] then
          null
        else
          let
            path = builtins.head frontier;
            rest = builtins.tail frontier;
            node = lastElem path;
          in
          if node == null then
            null
          else if node == goal then
            path
          else
            let
              candidates = neighborsOf node;
              nexts = lib.filter (n: !(builtins.elem n visited)) candidates;
              visited' = visited ++ nexts;
              frontier' = rest ++ (map (n: path ++ [ n ]) nexts);
            in
            go visited' frontier';
    in
    if start == null || goal == null then null else go [ start ] [ [ start ] ];

  firstHopInterfaceToUnit =
    targetUnit:
    if currentNodeName == null || targetUnit == null then
      null
    else
      let
        path = findPath {
          start = currentNodeName;
          goal = targetUnit;
        };
        hop = if path != null && builtins.length path >= 2 then builtins.elemAt path 1 else null;
        adjacency =
          if hop != null then
            adjacencyForPair {
              a = currentNodeName;
              b = hop;

              linkNameMatches =
                if builtins.isString targetUnit && targetUnit != "" then
                  (ln: builtins.match ".*--access-${targetUnit}($|--).*" ln != null)
                else
                  null;
            }
          else
            null;
        linkName = if adjacency != null then adjacencyLinkName adjacency else null;
      in
      if linkName != null then interfaceNameForLink linkName else null;

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

          interfaceName = firstHopInterfaceToUnit attachment.unit;
        in
        if interfaceName != null then
          {
            name = attachment.name;
            value = interfaceName;
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
      null;

  explicitWanNames =
    if interfaceView != null && builtins.isAttrs interfaceView && interfaceView ? wanNames then
      sortedStrings interfaceView.wanNames
    else
      [ ];

  upstreamInterfaceNames =
    let
      matches =
        if currentNodeName != null && upstreamSelectorNodeName != null then
          lib.filter (
            adjacency:
            let
              units = adjacencyUnits adjacency;
            in
            builtins.length units == 2
            && builtins.elem currentNodeName units
            && builtins.elem upstreamSelectorNodeName units
          ) transitAdjacencies
        else
          [ ];

      linkNames = lib.filter (ln: ln != null) (map adjacencyLinkName matches);
      ifNames = lib.filter (n: n != null) (map interfaceNameForLink linkNames);
    in
    if ifNames != [ ] then
      sortedStrings ifNames
    else if explicitWanNames != [ ] then
      [ (builtins.head explicitWanNames) ]
    else
      [ ];

  upstreamAdjacencyLinkNames = lib.filter (ln: ln != null) (
    map adjacencyLinkName (
      if currentNodeName != null && upstreamSelectorNodeName != null then
        lib.filter (
          adjacency:
          let
            units = adjacencyUnits adjacency;
          in
          builtins.length units == 2
          && builtins.elem currentNodeName units
          && builtins.elem upstreamSelectorNodeName units
        ) transitAdjacencies
      else
        [ ]
    )
  );

  upstreamInterfacesForUplink =
    uplinkName:
    let
      candidates =
        if !builtins.isString uplinkName || uplinkName == "" then
          [ ]
        else
          let
            raw = [
              uplinkName
              "uplink-${uplinkName}"
            ];
          in
          if lib.hasPrefix "uplink-" uplinkName then
            raw
            ++ [
              lib.removePrefix
              "uplink-"
              uplinkName
            ]
          else
            raw;

      matches = lib.filter (
        ln:
        lib.any (
          candidate: builtins.isString candidate && candidate != "" && lib.hasInfix candidate ln
        ) candidates
      ) upstreamAdjacencyLinkNames;
    in
    sortedStrings (lib.filter (n: n != null) (map interfaceNameForLink matches));

  routesOf =
    entry:
    let
      routes = entryFieldOr entry "routes" null;
    in
    if builtins.isAttrs routes then
      lib.concatLists (builtins.attrValues routes)
    else if builtins.isList routes then
      routes
    else
      [ ];

  routeIsDefault =
    route:
    builtins.isAttrs route && ((route.dst or null) == "0.0.0.0/0" || (route.dst or null) == "::/0");

  exitUpstreamInterfaceNames = sortedStrings (
    map (entry: entry.name) (
      lib.filter (
        entry:
        builtins.elem (entry.name or null) upstreamInterfaceNames
        && builtins.any routeIsDefault (routesOf entry)
      ) interfaceEntries
    )
  );

  wanEndpointNames =
    if explicitWanNames != [ ] then
      explicitWanNames
    else if exitUpstreamInterfaceNames != [ ] then
      exitUpstreamInterfaceNames
    else
      upstreamInterfaceNames;

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

        providerTenants =
          if service ? providerTenants && builtins.isList service.providerTenants then
            lib.filter builtins.isString service.providerTenants
          else
            lib.filter (tenant: tenant != null) (map providerTenantFor providers);

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

  canonicalInterfaceTags =
    if
      currentSite ? policy
      && builtins.isAttrs currentSite.policy
      && currentSite.policy ? interfaceTags
      && builtins.isAttrs currentSite.policy.interfaceTags
    then
      currentSite.policy.interfaceTags
    else
      { };

  fallbackInterfaceTags =
    if
      communicationContract ? interfaceTags && builtins.isAttrs communicationContract.interfaceTags
    then
      communicationContract.interfaceTags
    else
      { };

  interfaceTags =
    if canonicalInterfaceTags != { } then canonicalInterfaceTags else fallbackInterfaceTags;

  normalizeToken =
    token:
    if builtins.hasAttr token interfaceTags && builtins.isString interfaceTags.${token} then
      interfaceTags.${token}
    else
      token;

  allKnownInterfaces = sortedStrings (
    (builtins.attrValues tenantInterfaceByName) ++ upstreamInterfaceNames
  );

  resolveStringEndpoint =
    endpoint:
    let
      token = normalizeToken endpoint;
      uplinkMatches = upstreamInterfacesForUplink token;
    in
    if token == "any" then
      allKnownInterfaces
    else if token == "wan" || token == "external-wan" then
      wanEndpointNames
    else if token == "upstream" then
      upstreamInterfaceNames
    else if uplinkMatches != [ ] then
      uplinkMatches
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
      && ((endpoint.name or null) == "wan" || (endpoint.name or null) == "external-wan")
    then
      wanEndpointNames
    else if kind == "external" && (endpoint.name or null) == "upstream" then
      upstreamInterfaceNames
    else if kind == "external" && endpoint ? uplinks && builtins.isList endpoint.uplinks then
      let
        resolved = sortedStrings (
          lib.concatMap (
            uplinkName:
            let
              matches = resolveStringEndpoint uplinkName;
            in
            if matches != [ ] then matches else wanEndpointNames
          ) endpoint.uplinks
        );
      in
      resolved
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

  missingTenantBindings = lib.filter (
    tenantName: !builtins.hasAttr tenantName tenantInterfaceByName
  ) (sortedStrings (map (attachment: attachment.name) tenantAttachments));

  authorityGaps = lib.unique (
    lib.optionals (currentNodeName == null) [
      "policy node identity could not be resolved from the rendered runtime target"
    ]
    ++ lib.optionals (interfaceTags == { }) [
      "policy interface tags are missing (README requires site.policy.interfaceTags canonically)"
    ]
    ++ lib.optionals (missingTenantBindings != [ ]) [
      "tenant attachments could not be bound to policy transit interfaces: ${builtins.toJSON missingTenantBindings}"
    ]
    ++ lib.optionals (upstreamSelectorNodeName != null && upstreamInterfaceNames == [ ]) [
      "upstream-selector transit binding could not be resolved for the policy node"
    ]
  );

  authoritativeBindings = authorityGaps == [ ];

  entityName =
    if builtins.isString containerName && containerName != "" then
      containerName
    else if builtins.isString unitName && unitName != "" then
      unitName
    else if runtimeTarget ? unitName && builtins.isString runtimeTarget.unitName then
      runtimeTarget.unitName
    else
      null;

  strictMode = roleName == "policy";

  _ =
    if strictMode && !authoritativeBindings then
      throw ''
        s88/ControlModule/firewall/mapping/policy-endpoints.nix: refusing to synthesize policy endpoint bindings

        container: ${toString entityName}
        role: policy
        gaps:
        ${builtins.concatStringsSep "\n" (map (line: "  - ${line}") authorityGaps)}
      ''
    else
      null;
in
{
  inherit
    resolveEndpoint
    allKnownInterfaces
    wanNames
    p2pNames
    localAdapterNames
    authoritativeBindings
    authorityGaps
    ;
}
