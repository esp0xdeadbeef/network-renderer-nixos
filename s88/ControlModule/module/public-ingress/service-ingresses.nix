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
      # FS-230-HDS-010-SDS-010-SMS-020: consume the explicit public-ingress
      # translation decision carried by the owning external allow relations.
      # translationMode = "none" is an explicit no-translation decision and
      # must suppress DNAT/SNAT materialization for this service tuple. A
      # translation-capable mode keeps the DNAT contract. Conflicting decisions
      # across the owning relations fail closed rather than guessing.
      translationModes =
        lib.unique (
          builtins.filter (mode: mode != null)
            (map
              (relation:
                let authority = attrOr (relation.publicIngressTupleAuthority or null);
                in if authority ? translationMode then authority.translationMode else null)
              relations)
        );
      translationMode =
        if translationModes == [ ] then
          null
        else if builtins.length translationModes == 1 then
          builtins.head translationModes
        else
          fail "CPM service '${serviceName}' has conflicting public-ingress translationMode decisions: ${builtins.concatStringsSep ", " translationModes}";
    in
    if relations == [ ] || matches == [ ] then
      fail "CPM does not expose service '${serviceName}' from an external relation"
    else
      builtins.seq _providerBinding
        {
          inherit serviceName matches translationMode;
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
