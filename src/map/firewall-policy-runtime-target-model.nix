{
  lib,
  normalizeCommunicationContract,
  lookupSiteServiceInputs,
}:
{
  normalizedModel,
  artifactContext,
}:
let
  ensureAttrs =
    name: value:
    if builtins.isAttrs value then
      value
    else
      throw "network-renderer-nixos: expected ${name} to be an attribute set";

  ensureList =
    name: value:
    if builtins.isList value then
      value
    else
      throw "network-renderer-nixos: expected ${name} to be a list";

  ensureString =
    name: value:
    if builtins.isString value && value != "" then
      value
    else
      throw "network-renderer-nixos: expected ${name} to be a non-empty string";

  ensureInt =
    name: value:
    if builtins.isInt value then
      value
    else
      throw "network-renderer-nixos: expected ${name} to be an integer";

  json = value: builtins.toJSON value;

  sortedByPriority =
    rules:
    lib.sort (
      a: b: if a.priority == b.priority then a.order < b.order else a.priority < b.priority
    ) rules;

  context = ensureAttrs "artifactContext" artifactContext;

  enterpriseName =
    if context ? enterpriseName then
      ensureString "artifactContext.enterpriseName" context.enterpriseName
    else
      throw "network-renderer-nixos: artifactContext is missing enterpriseName";

  siteName =
    if context ? siteName then
      ensureString "artifactContext.siteName" context.siteName
    else
      throw "network-renderer-nixos: artifactContext is missing siteName";

  runtimeTargetName =
    if context ? runtimeTargetName then
      ensureString "artifactContext.runtimeTargetName" context.runtimeTargetName
    else
      throw "network-renderer-nixos: artifactContext is missing runtimeTargetName";

  runtimeTarget =
    if context ? runtimeTarget then
      ensureAttrs "artifactContext.runtimeTarget" context.runtimeTarget
    else
      throw "network-renderer-nixos: artifactContext is missing runtimeTarget";

  siteServiceInputs = lookupSiteServiceInputs {
    inherit
      normalizedModel
      enterpriseName
      siteName
      ;
  };

  communicationContract =
    if siteServiceInputs ? communicationContract then
      normalizeCommunicationContract siteServiceInputs.communicationContract
    else
      throw ''
        network-renderer-nixos: siteServiceInputs is missing communicationContract for runtime target '${runtimeTargetName}'
        runtimeTarget=${json runtimeTarget}
        siteServiceInputs=${json siteServiceInputs}
      '';

  ownership =
    if siteServiceInputs ? ownership then
      ensureAttrs "siteServiceInputs.ownership" siteServiceInputs.ownership
    else
      throw ''
        network-renderer-nixos: siteServiceInputs is missing ownership for runtime target '${runtimeTargetName}'
        runtimeTarget=${json runtimeTarget}
        siteServiceInputs=${json siteServiceInputs}
      '';

  forwardingIntent =
    if runtimeTarget ? forwardingIntent then
      ensureAttrs "runtimeTarget.forwardingIntent" runtimeTarget.forwardingIntent
    else
      throw "network-renderer-nixos: runtime target '${runtimeTargetName}' is missing forwardingIntent";

  transitInterfaces =
    if forwardingIntent ? transitInterfaces then
      map
        (
          interfaceName:
          ensureString "runtime target '${runtimeTargetName}'.forwardingIntent.transitInterfaces entry" interfaceName
        )
        (
          ensureList "runtime target '${runtimeTargetName}'.forwardingIntent.transitInterfaces" forwardingIntent.transitInterfaces
        )
    else
      throw "network-renderer-nixos: runtime target '${runtimeTargetName}' is missing forwardingIntent.transitInterfaces";

  egressIntent =
    if runtimeTarget ? egressIntent then
      ensureAttrs "runtime target '${runtimeTargetName}'.egressIntent" runtimeTarget.egressIntent
    else
      { };

  wanInterfaces =
    if egressIntent ? wanInterfaces then
      map
        (
          interfaceName:
          ensureString "runtime target '${runtimeTargetName}'.egressIntent.wanInterfaces entry" interfaceName
        )
        (
          ensureList "runtime target '${runtimeTargetName}'.egressIntent.wanInterfaces" egressIntent.wanInterfaces
        )
    else
      [ ];

  uplinkInterfaces =
    if egressIntent ? uplinks then
      map (
        interfaceName:
        ensureString "runtime target '${runtimeTargetName}'.egressIntent.uplinks entry" interfaceName
      ) (ensureList "runtime target '${runtimeTargetName}'.egressIntent.uplinks" egressIntent.uplinks)
    else
      [ ];

  externalInterfaceCandidates = lib.unique (
    wanInterfaces
    ++ uplinkInterfaces
    ++ lib.optional (lib.elem "upstream" transitInterfaces) "upstream"
    ++ lib.optional (lib.elem "wan" transitInterfaces) "wan"
  );

  externalInterface =
    if builtins.length externalInterfaceCandidates == 1 then
      builtins.head externalInterfaceCandidates
    else if builtins.length externalInterfaceCandidates == 0 then
      throw "network-renderer-nixos: policy runtime target '${runtimeTargetName}' is missing an external transit interface"
    else
      throw "network-renderer-nixos: policy runtime target '${runtimeTargetName}' resolves to multiple external transit interfaces";

  internalInterfaces = lib.filter (
    interfaceName: interfaceName != externalInterface
  ) transitInterfaces;

  internalInterface =
    if builtins.length internalInterfaces == 1 then
      builtins.head internalInterfaces
    else if builtins.length internalInterfaces == 0 then
      throw "network-renderer-nixos: policy runtime target '${runtimeTargetName}' is missing an internal transit interface"
    else
      throw "network-renderer-nixos: policy runtime target '${runtimeTargetName}' resolves to multiple internal transit interfaces";

  ownershipPrefixes =
    if ownership ? prefixes then
      ensureList "siteServiceInputs.ownership.prefixes" ownership.prefixes
    else
      throw ''
        network-renderer-nixos: ownership is missing prefixes for runtime target '${runtimeTargetName}'
        ownership=${json ownership}
        runtimeTarget=${json runtimeTarget}
      '';

  ownershipEndpoints =
    if ownership ? endpoints then
      ensureList "siteServiceInputs.ownership.endpoints" ownership.endpoints
    else
      throw ''
        network-renderer-nixos: ownership is missing endpoints for runtime target '${runtimeTargetName}'
        ownership=${json ownership}
        runtimeTarget=${json runtimeTarget}
      '';

  services = communicationContract.services;
  trafficTypes = communicationContract.trafficTypes;
  relations = communicationContract.relations;

  findService =
    serviceName:
    let
      matches = lib.filter (
        service:
        builtins.isAttrs service
        && service ? name
        && builtins.isString service.name
        && service.name == serviceName
      ) services;
    in
    if builtins.length matches == 1 then
      builtins.head matches
    else if builtins.length matches == 0 then
      throw "network-renderer-nixos: service '${serviceName}' is missing from communicationContract.services for runtime target '${runtimeTargetName}'"
    else
      throw "network-renderer-nixos: service '${serviceName}' appears multiple times in communicationContract.services for runtime target '${runtimeTargetName}'";

  findTrafficType =
    trafficTypeName:
    let
      matches = lib.filter (
        trafficType:
        builtins.isAttrs trafficType
        && trafficType ? name
        && builtins.isString trafficType.name
        && trafficType.name == trafficTypeName
      ) trafficTypes;
    in
    if builtins.length matches == 1 then
      builtins.head matches
    else if builtins.length matches == 0 then
      throw "network-renderer-nixos: traffic type '${trafficTypeName}' is missing from communicationContract.trafficTypes for runtime target '${runtimeTargetName}'"
    else
      throw "network-renderer-nixos: traffic type '${trafficTypeName}' appears multiple times in communicationContract.trafficTypes for runtime target '${runtimeTargetName}'";

  tenantPrefixes =
    tenantName:
    let
      matches = lib.filter (
        prefix:
        builtins.isAttrs prefix
        && prefix ? kind
        && prefix.kind == "tenant"
        && prefix ? name
        && builtins.isString prefix.name
        && prefix.name == tenantName
      ) ownershipPrefixes;

      ipv4s = lib.filter (value: value != null) (
        map (
          prefix:
          if prefix ? ipv4 then ensureString "tenant prefix '${tenantName}'.ipv4" prefix.ipv4 else null
        ) matches
      );

      ipv6s = lib.filter (value: value != null) (
        map (
          prefix:
          if prefix ? ipv6 then ensureString "tenant prefix '${tenantName}'.ipv6" prefix.ipv6 else null
        ) matches
      );

      _haveAnyPrefix =
        if ipv4s == [ ] && ipv6s == [ ] then
          throw "network-renderer-nixos: tenant '${tenantName}' has no prefixes for runtime target '${runtimeTargetName}'"
        else
          true;
    in
    builtins.seq _haveAnyPrefix {
      ipv4 = lib.unique ipv4s;
      ipv6 = lib.unique ipv6s;
    };

  tenantForEndpointProvider =
    providerName:
    let
      matches = lib.filter (
        endpoint:
        builtins.isAttrs endpoint
        && endpoint ? kind
        && endpoint.kind == "host"
        && endpoint ? name
        && builtins.isString endpoint.name
        && endpoint.name == providerName
      ) ownershipEndpoints;
    in
    if builtins.length matches == 1 then
      let
        endpoint = builtins.head matches;
      in
      if endpoint ? tenant then
        ensureString "ownership endpoint '${providerName}'.tenant" endpoint.tenant
      else
        throw "network-renderer-nixos: ownership endpoint '${providerName}' is missing tenant for runtime target '${runtimeTargetName}'"
    else if builtins.length matches == 0 then
      throw "network-renderer-nixos: provider '${providerName}' is missing from ownership.endpoints for runtime target '${runtimeTargetName}'"
    else
      throw "network-renderer-nixos: provider '${providerName}' appears multiple times in ownership.endpoints for runtime target '${runtimeTargetName}'";

  mergeTenantPrefixSets =
    tenantNames:
    let
      prefixSets = map tenantPrefixes tenantNames;
      ipv4s = lib.unique (lib.concatMap (prefixSet: prefixSet.ipv4) prefixSets);
      ipv6s = lib.unique (lib.concatMap (prefixSet: prefixSet.ipv6) prefixSets);
    in
    {
      inherit ipv4s ipv6s;
    };

  resolveEndpointSelector =
    endpoint:
    if builtins.isString endpoint then
      if endpoint == "any" then
        {
          kind = "any";
          ipv4s = [ ];
          ipv6s = [ ];
        }
      else
        throw "network-renderer-nixos: unsupported string endpoint '${endpoint}' in policy relation for runtime target '${runtimeTargetName}'"
    else
      let
        endpointDef = ensureAttrs "policy relation endpoint" endpoint;
        kind =
          if endpointDef ? kind then
            ensureString "policy relation endpoint.kind" endpointDef.kind
          else
            throw "network-renderer-nixos: policy relation endpoint is missing kind for runtime target '${runtimeTargetName}'";
      in
      if kind == "tenant" then
        let
          tenantName =
            if endpointDef ? name then
              ensureString "policy tenant endpoint.name" endpointDef.name
            else
              throw "network-renderer-nixos: tenant endpoint is missing name for runtime target '${runtimeTargetName}'";

          prefixSet = tenantPrefixes tenantName;
        in
        {
          kind = "tenant";
          ipv4s = prefixSet.ipv4;
          ipv6s = prefixSet.ipv6;
        }
      else if kind == "tenant-set" then
        let
          members =
            if endpointDef ? members then
              map (member: ensureString "policy tenant-set member" member) (
                ensureList "policy tenant-set members" endpointDef.members
              )
            else
              throw "network-renderer-nixos: tenant-set endpoint is missing members for runtime target '${runtimeTargetName}'";

          prefixSet = mergeTenantPrefixSets members;
        in
        {
          kind = "tenant-set";
          ipv4s = prefixSet.ipv4s;
          ipv6s = prefixSet.ipv6s;
        }
      else if kind == "service" then
        let
          serviceName =
            if endpointDef ? name then
              ensureString "policy service endpoint.name" endpointDef.name
            else
              throw "network-renderer-nixos: service endpoint is missing name for runtime target '${runtimeTargetName}'";

          serviceDef = findService serviceName;

          providers =
            if serviceDef ? providers then
              map (provider: ensureString "service '${serviceName}' provider" provider) (
                ensureList "service '${serviceName}'.providers" serviceDef.providers
              )
            else
              throw "network-renderer-nixos: service '${serviceName}' is missing providers for runtime target '${runtimeTargetName}'";

          providerTenantNames = lib.unique (map tenantForEndpointProvider providers);
          prefixSet = mergeTenantPrefixSets providerTenantNames;
        in
        {
          kind = "service";
          ipv4s = prefixSet.ipv4s;
          ipv6s = prefixSet.ipv6s;
        }
      else if kind == "external" then
        {
          kind = "external";
          ipv4s = [ ];
          ipv6s = [ ];
        }
      else
        throw "network-renderer-nixos: unsupported policy endpoint kind '${kind}' for runtime target '${runtimeTargetName}'";

  resolveTrafficTypeMatches =
    trafficTypeName:
    if trafficTypeName == "any" then
      [
        {
          family = "any";
          proto = null;
          dports = [ ];
        }
      ]
    else
      let
        trafficTypeDef = findTrafficType trafficTypeName;
        matches =
          if trafficTypeDef ? match then
            ensureList "traffic type '${trafficTypeName}'.match" trafficTypeDef.match
          else
            throw "network-renderer-nixos: traffic type '${trafficTypeName}' is missing match entries for runtime target '${runtimeTargetName}'";
      in
      map (
        match:
        let
          matchDef = ensureAttrs "traffic type '${trafficTypeName}' match entry" match;
          family =
            if matchDef ? family then
              ensureString "traffic type '${trafficTypeName}' match.family" matchDef.family
            else
              throw "network-renderer-nixos: traffic type '${trafficTypeName}' match is missing family for runtime target '${runtimeTargetName}'";

          proto =
            if matchDef ? proto then
              ensureString "traffic type '${trafficTypeName}' match.proto" matchDef.proto
            else
              throw "network-renderer-nixos: traffic type '${trafficTypeName}' match is missing proto for runtime target '${runtimeTargetName}'";

          dports =
            if matchDef ? dports then
              map (port: ensureInt "traffic type '${trafficTypeName}' dport" port) (
                ensureList "traffic type '${trafficTypeName}' match.dports" matchDef.dports
              )
            else
              [ ];
        in
        {
          inherit family proto dports;
        }
      ) matches;

  interfacePairsForRelation =
    sourceSelector: targetSelector:
    let
      sourceKind = sourceSelector.kind;
      targetKind = targetSelector.kind;
    in
    if sourceKind == "external" && targetKind == "external" then
      throw "network-renderer-nixos: policy relation cannot map external-to-external traffic on runtime target '${runtimeTargetName}'"
    else if sourceKind == "external" then
      [
        {
          iifname = externalInterface;
          oifname = internalInterface;
        }
      ]
    else if targetKind == "external" then
      [
        {
          iifname = internalInterface;
          oifname = externalInterface;
        }
      ]
    else if targetKind == "any" then
      [
        {
          iifname = internalInterface;
          oifname = internalInterface;
        }
        {
          iifname = internalInterface;
          oifname = externalInterface;
        }
      ]
    else
      [
        {
          iifname = internalInterface;
          oifname = internalInterface;
        }
      ];

  familiesForMatch =
    sourceSelector: targetSelector: trafficMatch:
    let
      requestedFamilies =
        if trafficMatch.family == "ipv4" then
          [ "ipv4" ]
        else if trafficMatch.family == "ipv6" then
          [ "ipv6" ]
        else if trafficMatch.family == "any" then
          [
            "ipv4"
            "ipv6"
          ]
        else
          throw "network-renderer-nixos: unsupported traffic match family '${trafficMatch.family}' for runtime target '${runtimeTargetName}'";
    in
    lib.filter (
      family:
      let
        sourceOkay =
          if sourceSelector.kind == "external" || sourceSelector.kind == "any" then
            true
          else if family == "ipv4" then
            sourceSelector.ipv4s != [ ]
          else
            sourceSelector.ipv6s != [ ];

        targetOkay =
          if targetSelector.kind == "external" || targetSelector.kind == "any" then
            true
          else if family == "ipv4" then
            targetSelector.ipv4s != [ ]
          else
            targetSelector.ipv6s != [ ];
      in
      sourceOkay && targetOkay
    ) requestedFamilies;

  mapRelationRules =
    relationIndex: relation:
    let
      relationDef = ensureAttrs "communicationContract.relations[${toString relationIndex}]" relation;

      relationId =
        if relationDef ? id then
          ensureString "communicationContract.relations[${toString relationIndex}].id" relationDef.id
        else
          throw "network-renderer-nixos: relation ${toString relationIndex} is missing id for runtime target '${runtimeTargetName}'";

      priority =
        if relationDef ? priority then
          ensureInt "communicationContract.relations[${toString relationIndex}].priority" relationDef.priority
        else
          throw "network-renderer-nixos: relation '${relationId}' is missing priority for runtime target '${runtimeTargetName}'";

      action =
        if relationDef ? action then
          ensureString "communicationContract.relations[${toString relationIndex}].action" relationDef.action
        else
          throw "network-renderer-nixos: relation '${relationId}' is missing action for runtime target '${runtimeTargetName}'";

      verdict =
        if action == "allow" then
          "accept"
        else if action == "deny" then
          "drop"
        else
          throw "network-renderer-nixos: unsupported relation action '${action}' for runtime target '${runtimeTargetName}'";

      sourceSelector =
        if relationDef ? from then
          resolveEndpointSelector relationDef.from
        else
          throw "network-renderer-nixos: relation '${relationId}' is missing from endpoint for runtime target '${runtimeTargetName}'";

      targetSelector =
        if relationDef ? to then
          resolveEndpointSelector relationDef.to
        else
          throw "network-renderer-nixos: relation '${relationId}' is missing to endpoint for runtime target '${runtimeTargetName}'";

      trafficTypeName =
        if relationDef ? trafficType then
          ensureString "communicationContract.relations[${toString relationIndex}].trafficType" relationDef.trafficType
        else
          throw "network-renderer-nixos: relation '${relationId}' is missing trafficType for runtime target '${runtimeTargetName}'";

      trafficMatches = resolveTrafficTypeMatches trafficTypeName;
      interfacePairs = interfacePairsForRelation sourceSelector targetSelector;

      expandedRules = lib.concatMap (
        interfacePair:
        lib.concatMap (
          trafficMatch:
          let
            families = familiesForMatch sourceSelector targetSelector trafficMatch;
          in
          if families == [ ] then
            [ ]
          else
            map (family: {
              order = relationIndex;
              inherit priority verdict family;
              chain = "forward";
              comment = relationId;
              iifname = interfacePair.iifname;
              oifname = interfacePair.oifname;
              saddr4s = if family == "ipv4" then sourceSelector.ipv4s else [ ];
              saddr6s = if family == "ipv6" then sourceSelector.ipv6s else [ ];
              daddr4s = if family == "ipv4" then targetSelector.ipv4s else [ ];
              daddr6s = if family == "ipv6" then targetSelector.ipv6s else [ ];
              proto = trafficMatch.proto;
              dports = trafficMatch.dports;
              applyTcpMssClamp = false;
            }) families
        ) trafficMatches
      ) interfacePairs;

      _haveExpandedRules =
        if expandedRules == [ ] then
          throw "network-renderer-nixos: relation '${relationId}' produced no concrete firewall rules for runtime target '${runtimeTargetName}'"
        else
          true;
    in
    builtins.seq _haveExpandedRules expandedRules;

  rawRules =
    if relations == [ ] then
      throw ''
        network-renderer-nixos: policy runtime target '${runtimeTargetName}' has no communication relations
        communicationContract=${json communicationContract}
        siteServiceInputs=${json siteServiceInputs}
        runtimeTarget=${json runtimeTarget}
      ''
    else
      lib.concatMap (
        relationIndex: mapRelationRules relationIndex (builtins.elemAt relations relationIndex)
      ) (lib.range 0 (builtins.length relations - 1));

  rules = sortedByPriority rawRules;

  _haveRules =
    if rules == [ ] then
      throw "network-renderer-nixos: policy runtime target '${runtimeTargetName}' produced no firewall rules"
    else
      true;
in
builtins.seq _haveRules {
  inherit runtimeTargetName;
  tableFamily = "inet";
  tableName = "filter";
  chains = {
    forward = {
      type = "filter";
      hook = "forward";
      priority = 0;
      policy = "drop";
      rules = rules;
    };
  };
}
