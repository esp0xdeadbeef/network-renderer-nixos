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

  normalizeRuntimeForward =
    cpmRoot: index: forward:
    let
      runtimePath = "runtimeFacts.publicIngress.runtimeForwards[${toString index}]";
    in
    (builtins.removeAttrs forward [ "publicIPv4" "publicIPv4SecretPath" ])
    // publicIPv4Binding {
      path = runtimePath;
      value = forward;
      setName = "s88_public_runtime_${toString index}";
    }
    // {
      targetIPv4 =
        if strOrNull (forward.targetIPv4 or null) != null then
          forward.targetIPv4
        else
          runtimeTargetAddress4 cpmRoot (attrOr (forward.target or null));
    }
    // {
      comment = forward.comment or "s88-public-runtime-forward-${toString index}";
    };

  runtimeForwardsFor =
    { cpmRoot, publicIngressFacts }:
    lib.imap0 (idx: forward: normalizeRuntimeForward cpmRoot idx (attrOr forward)) (
      listOr (publicIngressFacts.runtimeForwards or null)
    );

  serviceIngressesFor = { cpmRoot, publicIngressFacts }:
    lib.concatMap
      (item:
        let
          serviceNames =
            lib.sort builtins.lessThan (
              builtins.attrNames (attrOr (((publicIngressFacts.services or { }).${item.enterpriseName} or { }).${item.siteName} or { }))
            );
        in
        map
          (serviceName:
            let
              binding = serviceBindingFor item.site serviceName;
              providers = listOr (binding.providers or null);
              relations = externalAllowServiceRelations item.site serviceName;
              matches = lib.concatMap (relation: relationMatches item.site relation) relations;
              runtimeFact = serviceRuntimeFact publicIngressFacts item.enterpriseName item.siteName serviceName;
              service = serviceDefinitionFor item.site serviceName;
              _providerBinding =
                if providers != [ ] then true else fail "CPM service '${serviceName}' has no provider binding";
            in
            if relations == [ ] || matches == [ ] then
              fail "CPM does not expose service '${serviceName}' from an external relation"
            else
              builtins.seq _providerBinding {
                inherit serviceName matches;
                targetIPv4 = singleProviderEndpoint4 serviceName service;
                gateway4 = runtimeFact.gateway4 or null;
                routeDestination4 = runtimeFact.routeDestination4 or null;
                comment = "s88-public-service-${serviceName}";
              } // publicIPv4Binding {
                path = "runtimeFacts.publicIngress.services.${item.enterpriseName}.${item.siteName}.${serviceName}";
                value = runtimeFact;
                setName = "s88_public_service_${nftName item.enterpriseName}_${nftName item.siteName}_${nftName serviceName}";
              })
          serviceNames)
      (siteItemsFrom cpmRoot);
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
