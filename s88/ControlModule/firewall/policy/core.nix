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

  wanNames = sortedStrings (interfaceWanNames ++ wanIfs);
  lanNames = sortedStrings (interfaceLanNames ++ lanIfs);

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

  isWanToServiceAllow =
    relation:
    (relation.action or "allow") == "allow"
    && builtins.isAttrs (relation.from or null)
    && (relation.from.kind or null) == "external"
    && (relation.from.name or null) == "wan"
    && builtins.isAttrs (relation.to or null)
    && (relation.to.kind or null) == "service"
    && builtins.isString (relation.to.name or null)
    && builtins.hasAttr relation.to.name serviceDefinitions;

  serviceNatEntries = lib.concatMap (
    relation:
    let
      serviceName = relation.to.name;
      relationName = relationNameOf relation;
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
              inherit relationName serviceName target;
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

  forwardPairs =
    if useExplicitForwarding then
      forwardingIntent.coreForwardPairs or [ ]
    else
      lib.optionals (lanNames != [ ] && wanNames != [ ]) [
        {
          "in" = lanNames;
          "out" = wanNames;
          action = "accept";
          comment = "core-lan-to-wan";
        }
      ];

  natInterfaces =
    if useExplicitNat then
      forwardingIntent.coreNatInterfaces or [ ]
    else if fallbackNatEnabled then
      wanNames
    else
      [ ];

  portForwardForwardRules = map (
    entry:
    let
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
    "iifname ${
      if builtins.length wanNames == 1 then
        "\"${builtins.head wanNames}\""
      else
        "{ ${builtins.concatStringsSep ", " (map (name: "\"${name}\"") wanNames)} }"
    } oifname ${
      if builtins.length lanNames == 1 then
        "\"${builtins.head lanNames}\""
      else
        "{ ${builtins.concatStringsSep ", " (map (name: "\"${name}\"") lanNames)} }"
    } ${matchExpr} accept comment \"${relationNameOf { id = entry.relationName; }}\""
  ) serviceNatEntries;

  natPreroutingRules4 = map (
    entry:
    let
      l4Match = renderL4Match {
        inherit (entry) proto dport;
      };
    in
    "iifname ${
      if builtins.length wanNames == 1 then
        "\"${builtins.head wanNames}\""
      else
        "{ ${builtins.concatStringsSep ", " (map (name: "\"${name}\"") wanNames)} }"
    } ${l4Match} dnat to ${entry.target} comment \"${entry.relationName}\""
  ) (lib.filter (entry: entry.family == "ipv4") serviceNatEntries);

  natPreroutingRules6 = map (
    entry:
    let
      l4Match = renderL4Match {
        inherit (entry) proto dport;
      };
    in
    "iifname ${
      if builtins.length wanNames == 1 then
        "\"${builtins.head wanNames}\""
      else
        "{ ${builtins.concatStringsSep ", " (map (name: "\"${name}\"") wanNames)} }"
    } ${l4Match} dnat to ${entry.target} comment \"${entry.relationName}\""
  ) (lib.filter (entry: entry.family == "ipv6") serviceNatEntries);

  clampMssInterfaces =
    if useExplicitNat || useExplicitForwarding then
      forwardingIntent.coreClampMssInterfaces or [ ]
    else
      wanNames;

  inputRules = [
    ''
      icmpv6 type { nd-neighbor-solicit, nd-neighbor-advert, nd-router-solicit, nd-router-advert } accept comment "allow-ipv6-nd-ra"
    ''
  ];

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
