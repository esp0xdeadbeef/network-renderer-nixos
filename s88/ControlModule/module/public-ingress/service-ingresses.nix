{ lib
, helpers
,
}:

let
  inherit (helpers)
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
in
{ cpmRoot, publicIngressFacts }:
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
      builtins.seq _providerBinding
        {
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
  (siteItemsFrom cpmRoot)
