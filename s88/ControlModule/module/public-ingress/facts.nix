{ lib }:
let
  fail = message: throw "network-renderer-nixos public-ingress: ${message}";
  attrOr = value: if builtins.isAttrs value then value else { };
  listOr = value: if builtins.isList value then value else [ ];
  strOrNull = value: if builtins.isString value && value != "" then value else null;
  requiredString = path: value:
    let stringValue = strOrNull value;
    in if stringValue == null then fail "${path} is required" else stringValue;
  stripMask = value: builtins.head (lib.splitString "/" (toString value));
  sortedUniqueInts = values:
    lib.sort (left: right: left < right) (lib.unique (builtins.filter builtins.isInt values));
  nftName = value:
    lib.replaceStrings
      [ "-" "." ":" "/" "::" ]
      [ "_" "_" "_" "_" "_" ]
      value;

  publicIPv4Binding =
    { path, value, setName }:
    let
      publicIPv4 = strOrNull (value.publicIPv4 or null);
      publicIPv4SecretPath = strOrNull (value.publicIPv4SecretPath or null);
    in
    if publicIPv4 != null && publicIPv4SecretPath != null then
      fail "${path} must set only one of publicIPv4 or publicIPv4SecretPath"
    else if publicIPv4 != null then
      { inherit publicIPv4; }
    else if publicIPv4SecretPath != null then
      {
        inherit publicIPv4SecretPath;
        publicIPv4SetName = setName;
        publicIPv4AssignToBridge = value.assignToBridge or false;
      }
    else
      fail "${path}.publicIPv4 or ${path}.publicIPv4SecretPath is required";

  cpmDataFrom = controlPlane:
    if builtins.isAttrs (controlPlane.control_plane_model.data or null) then
      controlPlane.control_plane_model.data
    else if builtins.isAttrs (controlPlane.data or null) then
      controlPlane.data
    else
      fail "controlPlane must contain control_plane_model.data";

  serviceBindingFor = site: serviceName:
    attrOr (((attrOr ((attrOr (site.policy or { })).endpointBindings or { })).services or { }).${serviceName} or { });

  externalAllowServiceRelations = site: serviceName:
    let
      relationList =
        listOr (((attrOr ((attrOr (site.policy or { })).endpointBindings or { })).relations or null))
        ++ listOr (((attrOr (site.communicationContract or { })).relations or null))
        ++ listOr (site.relations or null);
    in
    builtins.filter
      (relation:
        let
          from = attrOr (relation.from or { });
          to = attrOr (relation.to or { });
        in
        (relation.action or null) == "allow"
        && (from.kind or null) == "external"
        && (to.kind or null) == "service"
        && (to.name or null) == serviceName)
      relationList;

  trafficTypeMatchFor = site: trafficTypeName:
    let
      matches =
        builtins.filter
          (trafficType:
            builtins.isAttrs trafficType
            && (trafficType.name or null) == trafficTypeName)
          (listOr (((attrOr (site.communicationContract or { })).trafficTypes or null)));
    in
    if trafficTypeName == null then
      [ ]
    else if builtins.length matches == 1 then
      listOr ((builtins.head matches).match or null)
    else
      fail "CPM traffic type '${trafficTypeName}' must have exactly one match definition";

  relationMatches = site: relation:
    let
      directMatches = listOr (relation.match or null);
    in
    if directMatches != [ ] then
      directMatches
    else
      trafficTypeMatchFor site (relation.trafficType or null);

  serviceRuntimeFact = publicIngressFacts: enterpriseName: siteName: serviceName:
    attrOr ((((publicIngressFacts.services or { }).${enterpriseName} or { }).${siteName} or { }).${serviceName} or { });

  serviceDefinitionFor = site: serviceName:
    let
      matches =
        builtins.filter
          (service: builtins.isAttrs service && (service.name or null) == serviceName)
          (listOr (site.services or null));
    in
    if builtins.length matches == 1 then
      builtins.head matches
    else
      fail "CPM service '${serviceName}' must have exactly one resolved service definition";

  singleProviderEndpoint4 = serviceName: service:
    let
      endpoints = listOr (service.providerEndpoints or null);
      endpoint =
        if builtins.length endpoints == 1 then
          builtins.head endpoints
        else
          fail "CPM service '${serviceName}' must have exactly one provider endpoint";
      addresses = listOr (endpoint.ipv4 or null);
    in
    if builtins.length addresses == 1 then
      builtins.head addresses
    else
      fail "CPM service '${serviceName}' provider endpoint must have exactly one IPv4 address";

  siteItemsFrom = cpmRoot:
    lib.concatMap
      (enterpriseName:
        let enterprise = attrOr cpmRoot.${enterpriseName};
        in
        map
          (siteName: {
            inherit enterpriseName siteName;
            site = attrOr enterprise.${siteName};
          })
          (lib.sort builtins.lessThan (builtins.attrNames enterprise)))
      (lib.sort builtins.lessThan (builtins.attrNames cpmRoot));

  helpers = {
    inherit
      attrOr
      listOr
      fail
      nftName
      publicIPv4Binding
      relationMatches
      serviceBindingFor
      externalAllowServiceRelations
      serviceRuntimeFact
      serviceDefinitionFor
      singleProviderEndpoint4
      siteItemsFrom
      ;
  };

  runtimeTargetAddress4 =
    cpmRoot: targetRef:
    let
      enterpriseName = requiredString "runtimeFacts.publicIngress.runtimeForwards[*].target.enterpriseName" (
        targetRef.enterpriseName or null
      );
      siteName = requiredString "runtimeFacts.publicIngress.runtimeForwards[*].target.siteName" (
        targetRef.siteName or null
      );
      runtimeTargetName = requiredString "runtimeFacts.publicIngress.runtimeForwards[*].target.runtimeTarget" (
        targetRef.runtimeTarget or null
      );
      interfaceName = requiredString "runtimeFacts.publicIngress.runtimeForwards[*].target.interface" (
        targetRef.interface or null
      );
      site = attrOr ((attrOr cpmRoot.${enterpriseName}).${siteName} or { });
      runtimeTarget = attrOr ((attrOr (site.runtimeTargets or { })).${runtimeTargetName} or { });
      interfaces = attrOr ((runtimeTarget.effectiveRuntimeRealization or { }).interfaces or { });
      iface = attrOr (interfaces.${interfaceName} or { });
    in
    stripMask (requiredString
      "control_plane_model.data.${enterpriseName}.${siteName}.runtimeTargets.${runtimeTargetName}.effectiveRuntimeRealization.interfaces.${interfaceName}.addr4"
      (iface.addr4 or null));

  publicServiceInputDports =
    cpmRoot:
    sortedUniqueInts (
      lib.concatMap
        (item:
        lib.concatMap
          (service:
          let
            serviceName = service.name or null;
            relations =
              if serviceName == null then
                [ ]
              else
                externalAllowServiceRelations item.site serviceName;
            matches = lib.concatMap (relation: relationMatches item.site relation) relations;
          in
          lib.concatMap (match: listOr (match.dports or null)) matches)
          (listOr (item.site.services or null)))
        (siteItemsFrom cpmRoot)
    );

  # FS-310-HDS-010-SDS-010-SMS-130: a runtime forward is a caller-supplied
  # runtime FACT, never policy authority. DNAT materialization requires a
  # corresponding public-ingress authority in the CPM artifact: an external
  # allow relation to a modeled service that carries a
  # publicIngressTupleAuthority translation decision and whose provider
  # endpoint (the integrated production host entry) owns the forward target
  # address. A synthetic-only runtime fact — one with no such CPM authority —
  # fails closed here instead of materializing DNAT.
  runtimeForwardAuthorityFor = cpmRoot: targetIPv4:
    let
      candidates = lib.concatMap
        (item:
          lib.concatMap
            (service:
              let
                serviceName = strOrNull ((attrOr service).name or null);
                endpointAddresses = lib.concatMap
                  (endpoint: map stripMask (listOr ((attrOr endpoint).ipv4 or null)))
                  (listOr ((attrOr service).providerEndpoints or null));
                authorityRelations =
                  if serviceName == null then
                    [ ]
                  else
                    builtins.filter
                      (relation:
                        strOrNull
                          ((attrOr (relation.publicIngressTupleAuthority or null)).translationMode
                            or null) != null)
                      (externalAllowServiceRelations item.site serviceName);
              in
              if builtins.elem targetIPv4 endpointAddresses && authorityRelations != [ ] then
                map
                  (relation: {
                    source = "cpm-artifact";
                    inherit (item) enterpriseName siteName;
                    inherit serviceName;
                    relationId = strOrNull (relation.id or relation.name or null);
                    translationMode =
                      (attrOr (relation.publicIngressTupleAuthority or null)).translationMode;
                  })
                  authorityRelations
              else
                [ ])
            (listOr (item.site.services or null)))
        (siteItemsFrom cpmRoot);
    in
    if candidates == [ ] then null else builtins.head candidates;

  normalizeRuntimeForward =
    cpmRoot: derivedInputDports: index: forward:
    let
      runtimePath = "runtimeFacts.publicIngress.runtimeForwards[${toString index}]";
      container = attrOr (forward.containerInterface or { });
      hasForwardInputDports = forward ? inputDports;
      hasContainerInputDports = container ? inputDports;
      targetIPv4 =
        if strOrNull (forward.targetIPv4 or null) != null then
          forward.targetIPv4
        else
          runtimeTargetAddress4 cpmRoot (attrOr (forward.target or null));
      publicIngressAuthority = runtimeForwardAuthorityFor cpmRoot targetIPv4;
      _requireAuthority =
        if publicIngressAuthority == null then
          throw "FS-310-HDS-010-SDS-010-SMS-130: ${runtimePath} (target ${toString targetIPv4}) is a caller-supplied synthetic runtime fact with no corresponding public-ingress authority in the CPM artifact (no external allow service relation carrying publicIngressTupleAuthority owns this target endpoint) — refusing DNAT materialization from runtime facts (diagnostic.synthetic-core-ingress-authority, FS-310-HDS-020-SDS-010-SMS-075 negative case 3)"
        else
          true;
    in
    builtins.seq _requireAuthority (
      (builtins.removeAttrs forward [ "publicIPv4" "publicIPv4SecretPath" ])
      // publicIPv4Binding {
        path = runtimePath;
        value = forward;
        setName = "s88_public_runtime_${toString index}";
      }
      // {
        inherit targetIPv4 publicIngressAuthority;
      }
      // {
        comment = forward.comment or "s88-public-runtime-forward-${toString index}";
      }
      // lib.optionalAttrs (!hasForwardInputDports && !hasContainerInputDports && derivedInputDports != [ ]) {
        inputDports = derivedInputDports;
      }
    );

  runtimeForwardsFor =
    { cpmRoot, publicIngressFacts }:
    let
      derivedInputDports = publicServiceInputDports cpmRoot;
    in
    lib.imap0 (idx: forward: normalizeRuntimeForward cpmRoot derivedInputDports idx (attrOr forward)) (
      listOr (publicIngressFacts.runtimeForwards or null)
    );

  serviceIngressesFor = import ./service-ingresses.nix { inherit lib helpers; };
in
{
  inherit
    attrOr
    listOr
    requiredString
    cpmDataFrom
    serviceIngressesFor
    runtimeForwardsFor
    ;
}
