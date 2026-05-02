{
  lib,
  interfaceView ? null,
  forwardingIntent ? null,
  communicationContract ? { },
  ownership ? { },
  inventory ? { },
  unitName ? null,
  runtimeTarget ? { },
  interfaces ? { },
  wanIfs ? [ ],
  lanIfs ? [ ],
  uplinks ? { },
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

  interfaceWanNames =
    if interfaceView != null && builtins.isAttrs interfaceView && interfaceView ? wanNames then
      interfaceView.wanNames
    else
      [ ];

  interfaceLanNames =
    if interfaceView != null && builtins.isAttrs interfaceView && interfaceView ? lanNames then
      interfaceView.lanNames
    else
      [ ];

  interfaceEntries =
    if interfaceView != null && builtins.isAttrs interfaceView && interfaceView ? interfaceEntries then
      lib.filter builtins.isAttrs interfaceView.interfaceEntries
    else
      [ ];

  wanEntries =
    if interfaceView != null && builtins.isAttrs interfaceView && interfaceView ? wanEntries then
      lib.filter builtins.isAttrs interfaceView.wanEntries
    else
      [ ];

  interfaceNamesFromRuntime =
    if builtins.isAttrs interfaces then
      map (
        ifName:
        let
          iface = interfaces.${ifName};
        in
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
          null
      ) (lib.sort builtins.lessThan (builtins.attrNames interfaces))
    else
      [ ];

  overlayNames = sortedStrings (
    map (
      entry:
      if
        (
          (entry ? sourceKind && entry.sourceKind == "overlay")
          || (
            entry ? backingRef
            && builtins.isAttrs entry.backingRef
            && (entry.backingRef.kind or null) == "overlay"
          )
          || (
            entry ? iface
            && builtins.isAttrs entry.iface
            && entry.iface ? backingRef
            && builtins.isAttrs entry.iface.backingRef
            && (entry.iface.backingRef.kind or null) == "overlay"
          )
        )
        && entry ? name
        && builtins.isString entry.name
      then
        entry.name
      else
        null
    ) interfaceEntries
  );

  overlayNamesFromRuntime = sortedStrings (
    lib.filter (
      name: builtins.isString name && (lib.hasPrefix "overlay" name || lib.hasPrefix "ovl-" name)
    ) interfaceNamesFromRuntime
  );
  overlayIngressNames = sortedStrings (overlayNames ++ overlayNamesFromRuntime);

  wanNames = sortedStrings (interfaceWanNames ++ wanIfs);
  lanNames = sortedStrings (interfaceLanNames ++ lanIfs);
  forwardEgressNames = sortedStrings (wanNames ++ overlayNames ++ overlayNamesFromRuntime);

  adapterNames = sortedStrings (wanNames ++ lanNames);

  uplinkNames =
    if builtins.isAttrs uplinks then lib.sort builtins.lessThan (builtins.attrNames uplinks) else [ ];

  trafficTypeDefinitions =
    if communicationContract ? trafficTypes && builtins.isList communicationContract.trafficTypes then
      builtins.listToAttrs (
        map
          (trafficType: {
            name = trafficType.name;
            value = trafficType;
          })
          (
            lib.filter (
              trafficType:
              builtins.isAttrs trafficType && trafficType ? name && builtins.isString trafficType.name
            ) communicationContract.trafficTypes
          )
      )
    else
      { };

  serviceDefinitions =
    if communicationContract ? services && builtins.isList communicationContract.services then
      builtins.listToAttrs (
        map
          (service: {
            name = service.name;
            value = service;
          })
          (
            lib.filter (
              service: builtins.isAttrs service && service ? name && builtins.isString service.name
            ) communicationContract.services
          )
      )
    else
      { };

  ownershipEndpoints =
    if ownership ? endpoints && builtins.isList ownership.endpoints then
      builtins.listToAttrs (
        map
          (endpoint: {
            name = endpoint.name;
            value = endpoint;
          })
          (
            lib.filter (
              endpoint: builtins.isAttrs endpoint && endpoint ? name && builtins.isString endpoint.name
            ) ownership.endpoints
          )
      )
    else
      { };

  inventoryEndpoints =
    if inventory ? endpoints && builtins.isAttrs inventory.endpoints then inventory.endpoints else { };

  relationNameOf =
    relation:
    if relation ? id && builtins.isString relation.id then
      relation.id
    else if relation ? name && builtins.isString relation.name then
      relation.name
    else
      builtins.toJSON relation;

  renderTrafficMatches =
    trafficTypeName:
    if trafficTypeName == null || trafficTypeName == "any" then
      [ ]
    else if builtins.hasAttr trafficTypeName trafficTypeDefinitions then
      let
        trafficType = trafficTypeDefinitions.${trafficTypeName};
        matches =
          if trafficType ? match && builtins.isList trafficType.match then trafficType.match else [ ];
      in
      lib.concatMap (
        match:
        let
          family = if match ? family && builtins.isString match.family then match.family else "any";
          families =
            if family == "ipv4" then
              [ "ipv4" ]
            else if family == "ipv6" then
              [ "ipv6" ]
            else
              [
                "ipv4"
                "ipv6"
              ];
          proto = if match ? proto && builtins.isString match.proto then match.proto else null;
          dports =
            if match ? dports && builtins.isList match.dports then
              lib.filter builtins.isInt match.dports
            else
              [ ];
          ports = if dports == [ ] then [ null ] else dports;
        in
        lib.concatMap (
          resolvedFamily:
          map (port: {
            family = resolvedFamily;
            inherit proto;
            dport = port;
          }) ports
        ) families
      ) matches
    else
      [ ];

  providerNamesForService =
    serviceName:
    if builtins.hasAttr serviceName serviceDefinitions then
      asStringList (serviceDefinitions.${serviceName}.providers or [ ])
    else
      [ ];

  providerTargetFor =
    {
      providerName,
      family,
      serviceName,
      relationName,
    }:
    let
      inventoryEntry =
        if builtins.hasAttr providerName inventoryEndpoints then
          inventoryEndpoints.${providerName}
        else
          { };
      addressField = if family == "ipv6" then "ipv6" else "ipv4";
      addresses =
        if builtins.isAttrs inventoryEntry && builtins.hasAttr addressField inventoryEntry then
          asStringList inventoryEntry.${addressField}
        else
          [ ];
    in
    if addresses == [ ] then
      null
    else if builtins.length addresses == 1 then
      builtins.head addresses
    else
      throw ''
        s88/ControlModule/firewall/policy/core.nix: service provider resolves to multiple ${family} addresses

        relation:
        ${builtins.toJSON relationName}

        service:
        ${builtins.toJSON serviceName}

        provider:
        ${builtins.toJSON providerName}

        addresses:
        ${builtins.toJSON addresses}
      '';

  allowRelations =
    if communicationContract ? relations && builtins.isList communicationContract.relations then
      lib.filter builtins.isAttrs communicationContract.relations
    else
      [ ];

  wanInterfacesForExternalEndpoint =
    endpoint:
    let
      externalName = endpoint.name or null;
      requestedUplinks =
        if endpoint ? uplinks && builtins.isList endpoint.uplinks then
          lib.filter builtins.isString endpoint.uplinks
        else
          [ ];
      fromNamedWan = builtins.elem externalName [
        "wan"
        "external-wan"
        "upstream"
      ];
      fromRequestedUplinks = sortedStrings (
        map (entry: entry.name) (
          lib.filter (
            entry:
            builtins.isString (entry.assignedUplinkName or null)
            && builtins.elem entry.assignedUplinkName requestedUplinks
          ) wanEntries
        )
      );
    in
    if requestedUplinks != [ ] then
      fromRequestedUplinks
    else if fromNamedWan then
      wanNames
    else
      [ ];

  isWanToServiceAllow =
    relation:
    (relation.action or "allow") == "allow"
    && builtins.isAttrs (relation.from or null)
    && (relation.from.kind or null) == "external"
    && builtins.isAttrs (relation.to or null)
    && (relation.to.kind or null) == "service"
    && builtins.isString (relation.to.name or null)
    && wanInterfacesForExternalEndpoint relation.from != [ ]
    && builtins.hasAttr relation.to.name serviceDefinitions;

  serviceNatEntries = lib.concatMap (
    relation:
    let
      serviceName = relation.to.name;
      relationName = relationNameOf relation;
      ingressIfNames = wanInterfacesForExternalEndpoint relation.from;
      service = serviceDefinitions.${serviceName};
      trafficTypeName =
        if relation ? trafficType && builtins.isString relation.trafficType then
          relation.trafficType
        else if service ? trafficType && builtins.isString service.trafficType then
          service.trafficType
        else
          null;
      trafficMatches = renderTrafficMatches trafficTypeName;
      providers = providerNamesForService serviceName;
      providerName =
        if builtins.length providers == 1 then
          builtins.head providers
        else if providers == [ ] then
          null
        else
          throw ''
            s88/ControlModule/firewall/policy/core.nix: service resolves to multiple providers; DNAT target would be ambiguous

            relation:
            ${builtins.toJSON relationName}

            service:
            ${builtins.toJSON serviceName}

            providers:
            ${builtins.toJSON providers}
          '';
      _validateProviderOwnership =
        if providerName == null then
          true
        else if builtins.hasAttr providerName ownershipEndpoints then
          true
        else
          throw ''
            s88/ControlModule/firewall/policy/core.nix: WAN-exposed service provider is missing from ownership.endpoints

            relation:
            ${builtins.toJSON relationName}

            service:
            ${builtins.toJSON serviceName}

            provider:
            ${builtins.toJSON providerName}
          '';
    in
    builtins.seq _validateProviderOwnership (
      lib.filter (entry: entry != null) (
        map (
          traffic:
          let
            target =
              if providerName == null then
                null
              else
                providerTargetFor {
                  inherit providerName serviceName relationName;
                  family = traffic.family;
                };
          in
          if target == null then
            null
          else
            {
              inherit
                relationName
                serviceName
                target
                ingressIfNames
                ;
              family = traffic.family;
              proto = traffic.proto;
              dport = traffic.dport;
            }
        ) trafficMatches
      )
    )
  ) (lib.filter isWanToServiceAllow allowRelations);

  renderInetFamilyMatch =
    family:
    if family == "ipv4" then
      "meta nfproto ipv4"
    else if family == "ipv6" then
      "meta nfproto ipv6"
    else
      "";

  renderL4Match =
    {
      proto,
      dport,
    }:
    if proto == null || proto == "any" then
      ""
    else if proto == "tcp" || proto == "udp" then
      let
        portExpr = if dport == null then "" else " ${proto} dport ${builtins.toString dport}";
      in
      "meta l4proto ${proto}${portExpr}"
    else
      "meta l4proto ${proto}";

  renderFamilyDaddr =
    {
      family,
      target,
    }:
    if family == "ipv4" then
      "ip daddr ${target}"
    else if family == "ipv6" then
      "ip6 daddr ${target}"
    else
      "";

  joinMatchParts =
    parts: lib.concatStringsSep " " (lib.filter (part: builtins.isString part && part != "") parts);

  uplinkHasIpv4 =
    uplinkName:
    let
      uplink = uplinks.${uplinkName};
      ipv4 = if uplink ? ipv4 && builtins.isAttrs uplink.ipv4 then uplink.ipv4 else null;
    in
    if ipv4 == null then
      true
    else if ipv4 ? enable then
      (ipv4.enable or false)
    else
      true;

  fallbackNatEnabled = wanNames != [ ] && (uplinkNames == [ ] || lib.any uplinkHasIpv4 uplinkNames);

  useExplicitForwarding =
    forwardingIntent != null
    && builtins.isAttrs forwardingIntent
    && (forwardingIntent.authoritativeCoreForwarding or false);

  useExplicitNat =
    forwardingIntent != null
    && builtins.isAttrs forwardingIntent
    && (forwardingIntent.authoritativeCoreNat or false);

  rawForwardPairs =
    if useExplicitForwarding then
      forwardingIntent.coreForwardPairs or [ ]
    else
      lib.optionals (lanNames != [ ] && forwardEgressNames != [ ]) [
        {
          "in" = lanNames;
          "out" = forwardEgressNames;
          action = "accept";
          comment = "core-lan-to-egress";
        }
      ];

  containsName = name: values: builtins.elem name (asStringList values);

  touchesUpstream =
    pair: (containsName "upstream" (pair."in" or [ ])) || (containsName "upstream" (pair."out" or [ ]));

  coreInputOverlayNames = overlayIngressNames;
  forwardPairs = rawForwardPairs;

  natInterfaces =
    if useExplicitNat then
      forwardingIntent.coreNatInterfaces or [ ]
    else
      [ ];

  portForwardForwardRules = map (
    entry:
    let
      ingressSelector =
        if builtins.length entry.ingressIfNames == 1 then
          "\"${builtins.head entry.ingressIfNames}\""
        else
          "{ ${builtins.concatStringsSep ", " (map (name: "\"${name}\"") entry.ingressIfNames)} }";
      matchExpr = joinMatchParts [
        (renderInetFamilyMatch entry.family)
        (renderFamilyDaddr {
          inherit (entry) family target;
        })
        (renderL4Match {
          inherit (entry) proto dport;
        })
      ];
    in
    "iifname ${ingressSelector} ${matchExpr} accept comment \"${
      relationNameOf { id = entry.relationName; }
    }\""
  ) serviceNatEntries;

  natPreroutingRules4 = map (
    entry:
    let
      ingressSelector =
        if builtins.length entry.ingressIfNames == 1 then
          "\"${builtins.head entry.ingressIfNames}\""
        else
          "{ ${builtins.concatStringsSep ", " (map (name: "\"${name}\"") entry.ingressIfNames)} }";
      l4Match = renderL4Match {
        inherit (entry) proto dport;
      };
    in
    "iifname ${ingressSelector} ${l4Match} dnat to ${entry.target} comment \"${entry.relationName}\""
  ) (lib.filter (entry: entry.family == "ipv4") serviceNatEntries);

  natPreroutingRules6 = map (
    entry:
    let
      ingressSelector =
        if builtins.length entry.ingressIfNames == 1 then
          "\"${builtins.head entry.ingressIfNames}\""
        else
          "{ ${builtins.concatStringsSep ", " (map (name: "\"${name}\"") entry.ingressIfNames)} }";
      l4Match = renderL4Match {
        inherit (entry) proto dport;
      };
    in
    "iifname ${ingressSelector} ${l4Match} dnat to ${entry.target} comment \"${entry.relationName}\""
  ) (lib.filter (entry: entry.family == "ipv6") serviceNatEntries);

  clampMssBaseInterfaces =
    if useExplicitNat || useExplicitForwarding then
      forwardingIntent.coreClampMssInterfaces or [ ]
    else
      wanNames;
  clampMssInterfaces =
    clampMssBaseInterfaces;

  inputRules = [
    ''
      icmpv6 type { nd-neighbor-solicit, nd-neighbor-advert, nd-router-solicit, nd-router-advert } accept comment "allow-ipv6-nd-ra"
    ''
  ]
  ++ lib.optional (coreInputOverlayNames != [ ]) ''
    iifname ${
      if builtins.length coreInputOverlayNames == 1 then
        "\"${builtins.head coreInputOverlayNames}\""
      else
        "{ ${builtins.concatStringsSep ", " (map (name: "\"${name}\"") coreInputOverlayNames)} }"
    } accept comment "allow-overlay-to-core"
  '';

  _validateCoreAdapterCount =
    if builtins.length adapterNames == 1 then
      throw ''
        s88/ControlModule/firewall/policy/core.nix: core role requires at least two adapters

        unitName:
        ${builtins.toJSON unitName}

        adapters:
        ${builtins.toJSON adapterNames}
      ''
    else
      true;
in
if wanNames == [ ] && lanNames == [ ] then
  null
else
  builtins.seq _validateCoreAdapterCount {
    tableName = "router";
    inputPolicy = "drop";
    outputPolicy = "accept";
    forwardPolicy = "drop";
    inherit
      inputRules
      forwardPairs
      natInterfaces
      natPreroutingRules4
      natPreroutingRules6
      clampMssInterfaces
      ;
    forwardRules = portForwardForwardRules;
  }
