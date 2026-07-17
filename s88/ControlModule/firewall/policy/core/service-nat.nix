{
  lib,
  catalog,
  interfaceSet,
  common,
  natIntent ? { },
}:

let
  inherit (common) asStringList relationNameOf sortedStrings;
  inherit (catalog)
    trafficTypeDefinitions
    serviceDefinitions
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
      requestedUplinks =
        if endpoint ? uplinks && builtins.isList endpoint.uplinks then
          lib.filter builtins.isString endpoint.uplinks
        else
          [ ];
      fromNamedWan = builtins.elem (endpoint.name or null) [
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
          ) interfaceSet.wanEntries
        )
      );
    in
    if requestedUplinks != [ ] then
      fromRequestedUplinks
    else if fromNamedWan then
      interfaceSet.wanNames
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

  isWanToServiceAllow =
    relation:
    let
      action =
        relation.action
          or (throw "FS-310-HDS-030-SDS-010-SMS-111: relation.action required by CPM provider contract, cannot default to 'allow'");
    in
    action == "allow"
    && builtins.isAttrs (relation.from or null)
    && (relation.from.kind or null) == "external"
    && builtins.isAttrs (relation.to or null)
    && (relation.to.kind or null) == "service"
    && builtins.isString (relation.to.name or null)
    && wanInterfacesForExternalEndpoint relation.from != [ ]
    && builtins.hasAttr relation.to.name serviceDefinitions;
in
{
  serviceNatEntries =
    let
      publicIngress =
        if builtins.isList (natIntent.publicIngress or null) then natIntent.publicIngress else null;
      nativeEntries =
        if publicIngress == null then
          null
        else
          lib.concatMap (
            record:
            let
              target = record.target or { };
              internalPath = record.internalPath or { };
              sourceTranslation = record.sourceTranslation or { };
              translationMode = record.translationMode or null;
              destinationTranslation = (record.destinationTranslation or false) == true;
              tupleRecords = if builtins.isList (record.tupleRecords or null) then record.tupleRecords else [ ];
              complete =
                builtins.isString (record.relationId or null)
                && builtins.isString (record.ingressInterface or null)
                && builtins.isString (internalPath.egressInterface or null)
                && builtins.isString (target.address or null)
                && builtins.isInt (target.port or null)
                && builtins.isString translationMode
                && builtins.isString (record.returnBehavior or null)
                && builtins.isString (record.sourcePreservation or null);
            in
            if !complete then
              throw "FS-310-HDS-020-SDS-010-SMS-075: CPM public-ingress record is incomplete; renderer refuses destination-translation inference"
            else if !destinationTranslation || translationMode == "none" then
              [ ]
            else
              map (
                tuple:
                if
                  !builtins.isString (tuple.protocol or null)
                  || !builtins.isInt (tuple.publicPort or null)
                  || !builtins.isInt (tuple.targetPort or null)
                then
                  throw "FS-310-HDS-020-SDS-010-SMS-075: CPM public-ingress tuple is incomplete"
                else
                  {
                    relationName = record.relationId;
                    serviceName = target.service or null;
                    target = target.address;
                    targetPort = tuple.targetPort;
                    publicPort = tuple.publicPort;
                    ingressIfNames = [ record.ingressInterface ];
                    egressIfName = internalPath.egressInterface;
                    family = "ipv4";
                    proto = tuple.protocol;
                    dport = tuple.publicPort;
                    sourceTranslation = sourceTranslation;
                    source = "cpm-nat-intent";
                  }
              ) tupleRecords
          ) publicIngress;
      legacyEntries = lib.concatMap (
        relation:
        let
          serviceName = relation.to.name;
          relationName = relationNameOf relation;
          ingressIfNames = wanInterfacesForExternalEndpoint relation.from;
          service = serviceDefinitions.${serviceName};
          trafficTypeName =
            if builtins.isString (relation.trafficType or null) then
              relation.trafficType
            else
              service.trafficType or null;
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
        in
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
          ) (renderTrafficMatches trafficTypeName)
        )
      ) (lib.filter isWanToServiceAllow allowRelations);
    in
    if nativeEntries == null then legacyEntries else nativeEntries;
}
