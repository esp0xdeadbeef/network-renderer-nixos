{ lib
, controlPlane
, hostName
}:

let
  controlPlaneModel =
    if builtins.isAttrs (controlPlane.control_plane_model or null) then
      controlPlane.control_plane_model
    else if builtins.isAttrs controlPlane then
      controlPlane
    else
      { };
  data = if builtins.isAttrs (controlPlaneModel.data or null) then controlPlaneModel.data else { };
  attrsOrEmpty = value: if builtins.isAttrs value then value else { };
  listOrEmpty = value: if builtins.isList value then value else [ ];
  sortedNames = attrs: lib.sort builtins.lessThan (builtins.attrNames attrs);

  allSites = lib.concatMap
    (enterpriseName:
      let enterprise = data.${enterpriseName};
      in if !builtins.isAttrs enterprise then [ ] else map
        (siteName: {
          inherit enterpriseName siteName;
          site = enterprise.${siteName};
        })
        (sortedNames enterprise))
    (sortedNames data);

  deploymentHosts = attrsOrEmpty (controlPlane.deploymentHosts or null);
  hostExistsInDeployment = builtins.hasAttr hostName deploymentHosts;

  siteAppliesToHost = entry:
    let targets = attrsOrEmpty (entry.site.runtimeTargets or null);
    in hostExistsInDeployment
      || lib.any
        (target: ((attrsOrEmpty target).deploymentHost or null) == hostName)
        (builtins.attrValues targets);

  sites = builtins.filter siteAppliesToHost allSites;

  formatDiagnostic = diagnostic:
    let
      traceId = diagnostic.traceId or "FS-560-HDS-010-SDS-020-SMS-010";
      code = diagnostic.code or "MODEL_CONTRACT_DIAGNOSTIC";
      sourceLayer = diagnostic.sourceLayer or "intent";
      message = diagnostic.message or "A model contract is incomplete and renderer materialization remains fail-closed";
    in
    "${traceId}: ${code} [${sourceLayer}]: ${message}";

  dnsWarningsFor = entry:
    let dns = attrsOrEmpty (entry.site.dns or null);
    in map formatDiagnostic (builtins.filter builtins.isAttrs (listOrEmpty (dns.warnings or null)));

  # FS-540: Detect DNS services that operate in legacy mode — the CPM did not
  # emit a recursionMode because no address-free recursiveDnsIntent or
  # localDnsSharingIntent reached the compiler. This means forwarders and
  # access-control are inventory-driven rather than intent-driven.
  legacyDnsTargetsFor = entry:
    let
      targets = attrsOrEmpty (entry.site.runtimeTargets or null);
      isLegacyDnsTarget = _targetName: target:
        let
          dns = attrsOrEmpty ((attrsOrEmpty target).services.dns or null);
          hasRecursionMode = (dns ? recursionMode) && dns.recursionMode != null;
          hasLocalForwardZones = builtins.isList (dns.localForwardZones or null) && dns.localForwardZones != [ ];
          hasRequesterPolicies = builtins.isList (dns.requesterPolicies or null) && dns.requesterPolicies != [ ];
          hasForwarders = builtins.isList (dns.forwarders or null) && dns.forwarders != [ ];
          hasLocalOnly = builtins.isAttrs (dns.localOnlyPolicy or null);
        in
        builtins.isAttrs dns
        && !hasRecursionMode
        && !hasLocalForwardZones
        && !hasRequesterPolicies
        && !hasLocalOnly;
    in
    builtins.filter
      (target: isLegacyDnsTarget "" target)
      (builtins.attrValues targets);

  legacyDnsWarningFor = entry:
    if legacyDnsTargetsFor entry != [ ] then
      [
        "FS-540-HDS-010-SDS-010-SMS-042: DNS_RECURSION_INTENT_ABSENT [intent]: one or more DNS runtime targets have no intent-driven recursion mode, named forward zones, or requester policies — forwarders and access-control are inventory-driven and may contain public resolvers or over-broad ACLs; define recursiveDnsIntent and localDnsSharingIntent in the site intent to switch to address-free modelled DNS"
      ]
    else
      [ ];

  reservationSourcesFor = entry:
    let
      targets = attrsOrEmpty (entry.site.runtimeTargets or null);
      sourcesForTarget = target:
        let
          advertisements = attrsOrEmpty ((attrsOrEmpty target).advertisements or null);
          advertisementEntries =
            listOrEmpty (advertisements.dhcp4 or null)
            ++ listOrEmpty (advertisements.dhcpv6 or null);
        in
        map (advertisement: (attrsOrEmpty advertisement).reservationSource or null) advertisementEntries;
    in
    builtins.filter builtins.isAttrs (lib.concatMap sourcesForTarget (builtins.attrValues targets));

  missingReservationPublicationFor = entry:
    builtins.any
      (source:
        (source.sourceClass or null) == "protected"
        && !builtins.isAttrs (source.namePublication or null))
      (reservationSourcesFor entry);

  runtimeIpv6PrefixesFor = entry:
    let routed = attrsOrEmpty (entry.site.routedPrefixes or null);
    in builtins.filter
      (prefix:
        builtins.isAttrs prefix
        && (prefix.family or null) == "ipv6"
        && (prefix.allocation or null) == "runtime")
      (lib.concatMap listOrEmpty (builtins.attrValues routed));

  pppoeClientsFor = entry:
    let targets = attrsOrEmpty (entry.site.runtimeTargets or null);
    in builtins.filter builtins.isAttrs (map
      (target: ((((attrsOrEmpty target).services or { }).pppoe or { }).client or null))
      (builtins.attrValues targets));

  missingPdContractFor = entry:
    let clients = pppoeClientsFor entry;
    in runtimeIpv6PrefixesFor entry != [ ]
      && clients != [ ]
      && !builtins.any (client: builtins.isAttrs (client.ipv6 or null)) clients;

  trafficTypesFor = entry:
    let contract = attrsOrEmpty (entry.site.communicationContract or null);
    in listOrEmpty (contract.trafficTypes or null);

  relationSupportsIpv6 = entry: relation:
    let
      trafficTypeName = relation.trafficType or null;
      definitions = builtins.filter
        (trafficType: ((attrsOrEmpty trafficType).name or null) == trafficTypeName)
        (trafficTypesFor entry);
      matches = lib.concatMap
        (trafficType: listOrEmpty ((attrsOrEmpty trafficType).match or null))
        definitions;
    in
    builtins.any
      (match:
        let family = (attrsOrEmpty match).family or "any";
        in family == "any" || family == "ipv6")
      matches;

  publicIngressRelationsFor = entry:
    builtins.filter
      (relation: builtins.isAttrs ((attrsOrEmpty relation).publicIngressTupleAuthority or null))
      (listOrEmpty (entry.site.relations or null));

  targetServiceFor = relation:
    let
      authority = attrsOrEmpty (relation.publicIngressTupleAuthority or null);
      endpoint = attrsOrEmpty (relation.to or null);
    in authority.targetService or endpoint.name or null;

  isIpv6IngressAuthority = relation:
    let authority = attrsOrEmpty (relation.publicIngressTupleAuthority or null);
    in (authority.family or null) == "ipv6"
      && (authority.translationMode or null) == "none";

  missingIpv6PublicIngressFor = entry:
    let
      relations = publicIngressRelationsFor entry;
      ipv4Authorities = builtins.filter
        (relation:
          let authority = attrsOrEmpty (relation.publicIngressTupleAuthority or null);
          in (authority.translationMode or null) == "napt"
            && ((authority.family or null) == null || authority.family == "ipv4")
            && relationSupportsIpv6 entry relation)
        relations;
      hasIpv6Peer = ipv4Relation:
        let targetService = targetServiceFor ipv4Relation;
        in builtins.any
          (candidate:
            isIpv6IngressAuthority candidate
            && targetServiceFor candidate == targetService)
          relations;
    in
    builtins.any (relation: !hasIpv6Peer relation) ipv4Authorities;

  generatedWarningsFor = entry:
    lib.optional (missingReservationPublicationFor entry)
      "FS-560-HDS-010-SDS-010-SMS-050: PROTECTED_RESERVATION_NAME_PUBLICATION_MISSING [inventory]: protected reservation scopes exist without an explicit renderer-owned name-publication contract"
    ++ lib.optional (missingPdContractFor entry)
      "FS-800-HDS-030-SDS-020-SMS-020: PPPOE_IPV6_PD_CONTRACT_MISSING [inventory]: runtime IPv6 tenant prefixes exist but the PPPoE client has no explicit DHCPv6-PD IAID and request contract"
    ++ lib.optional (missingIpv6PublicIngressFor entry)
      "FS-310-HDS-010-SDS-010-SMS-075: PUBLIC_INGRESS_IPV6_AUTHORITY_MISSING [intent]: an IPv6-capable public service relation has IPv4 NAPT authority but no explicit scoped IPv6 no-translation ingress relation"
    ++ legacyDnsWarningFor entry;
in
{
  warnings = lib.unique (lib.concatMap
    (entry: dnsWarningsFor entry ++ generatedWarningsFor entry)
    sites);
}
