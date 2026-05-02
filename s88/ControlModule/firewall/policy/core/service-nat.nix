{
  lib,
  catalog,
  interfaceSet,
  common,
}:

let
  inherit (common) asStringList relationNameOf sortedStrings;
  inherit
    (catalog)
    trafficTypeDefinitions
    serviceDefinitions
    ownershipEndpoints
    inventoryEndpoints
    allowRelations
    ;

  renderTrafficMatches =
    trafficTypeName:
    if trafficTypeName == null || trafficTypeName == "any" then
      [ ]
    else if builtins.hasAttr trafficTypeName trafficTypeDefinitions then
      let
        trafficType = trafficTypeDefinitions.${trafficTypeName};
        matches = if trafficType ? match && builtins.isList trafficType.match then trafficType.match else [ ];
      in
      lib.concatMap (
        match:
        let
          family = if match ? family && builtins.isString match.family then match.family else "any";
          families = if family == "ipv4" then [ "ipv4" ] else if family == "ipv6" then [ "ipv6" ] else [ "ipv4" "ipv6" ];
          proto = if match ? proto && builtins.isString match.proto then match.proto else null;
          dports = if match ? dports && builtins.isList match.dports then lib.filter builtins.isInt match.dports else [ ];
        in
        lib.concatMap (
          resolvedFamily:
          map (port: {
            family = resolvedFamily;
            inherit proto;
            dport = port;
          }) (if dports == [ ] then [ null ] else dports)
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

  wanInterfacesForExternalEndpoint =
    endpoint:
    let
      requestedUplinks = if endpoint ? uplinks && builtins.isList endpoint.uplinks then lib.filter builtins.isString endpoint.uplinks else [ ];
      fromNamedWan = builtins.elem (endpoint.name or null) [ "wan" "external-wan" "upstream" ];
      fromRequestedUplinks = sortedStrings (
        map (entry: entry.name) (
          lib.filter (
            entry: builtins.isString (entry.assignedUplinkName or null) && builtins.elem entry.assignedUplinkName requestedUplinks
          ) interfaceSet.wanEntries
        )
      );
    in
    if requestedUplinks != [ ] then fromRequestedUplinks else if fromNamedWan then interfaceSet.wanNames else [ ];

  providerTargetFor =
    { providerName, family, serviceName, relationName }:
    let
      inventoryEntry = if builtins.hasAttr providerName inventoryEndpoints then inventoryEndpoints.${providerName} else { };
      addressField = if family == "ipv6" then "ipv6" else "ipv4";
      addresses = if builtins.isAttrs inventoryEntry && builtins.hasAttr addressField inventoryEntry then asStringList inventoryEntry.${addressField} else [ ];
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
in
{
  serviceNatEntries = lib.concatMap (
    relation:
    let
      serviceName = relation.to.name;
      relationName = relationNameOf relation;
      ingressIfNames = wanInterfacesForExternalEndpoint relation.from;
      service = serviceDefinitions.${serviceName};
      trafficTypeName = if builtins.isString (relation.trafficType or null) then relation.trafficType else service.trafficType or null;
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
        if providerName == null || builtins.hasAttr providerName ownershipEndpoints then
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
            target = if providerName == null then null else providerTargetFor { inherit providerName serviceName relationName; family = traffic.family; };
          in
          if target == null then
            null
          else
            {
              inherit relationName serviceName target ingressIfNames;
              family = traffic.family;
              proto = traffic.proto;
              dport = traffic.dport;
            }
        ) (renderTrafficMatches trafficTypeName)
      )
    )
  ) (lib.filter isWanToServiceAllow allowRelations);
}
