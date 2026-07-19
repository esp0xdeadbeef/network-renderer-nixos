{ lib, renderedModel, forwardingIntent ? { } }:

let
  runtimeTarget =
    if renderedModel ? runtimeTarget && builtins.isAttrs renderedModel.runtimeTarget then
      renderedModel.runtimeTarget
    else
      { };

  dnsService =
    if
      runtimeTarget ? services && builtins.isAttrs runtimeTarget.services && runtimeTarget.services ? dns
    then
      runtimeTarget.services.dns
    else
      null;

  dnsAuthority =
    if builtins.isAttrs dnsService then
      import ./authority.nix { inherit lib dnsService; }
    else
      null;

  stringList = value:
    if builtins.isList value then lib.filter builtins.isString value else [ ];

  asList =
    value:
    if value == null then
      [ ]
    else if builtins.isList value then
      value
    else
      [ value ];

  requireNonEmptyString =
    path: value:
    if builtins.isString value && value != "" then
      value
    else
      throw "NixOS DNS renderer requires ${path} to be a non-empty string";

  requireStringList =
    path: value:
    if
      builtins.isList value
      && value != [ ]
      && builtins.all (entry: builtins.isString entry && entry != "") value
    then
      value
    else
      throw "NixOS DNS renderer requires ${path} to be a non-empty string list";

  safeStem = name: builtins.replaceStrings [ "/" ":" " " ] [ "-" "-" "-" ] name;

  protectedReservationPublications =
    let
      raw =
        if builtins.isList (dnsService.protectedReservationPublications or null) then
          dnsService.protectedReservationPublications
        else
          [ ];
      normalized = builtins.genList (
        idx:
        let
          entryPath = "services.dns.protectedReservationPublications[${builtins.toString idx}]";
          rawPublication = builtins.elemAt raw idx;
          publication =
            if builtins.isAttrs rawPublication then
              rawPublication
            else
              throw "NixOS DNS renderer requires ${entryPath} to be an explicit publication contract";
          source = if builtins.isAttrs (publication.source or null) then publication.source else { };
          scopeId = requireNonEmptyString "${entryPath}.scopeId" (publication.scopeId or null);
          namespace = requireNonEmptyString "${entryPath}.namespace" (publication.namespace or null);
          ownerScope = requireNonEmptyString "${entryPath}.ownerScope" (publication.ownerScope or null);
          requesterScopes = requireStringList "${entryPath}.requesterScopes" (publication.requesterScopes or null);
          recordClasses = requireStringList "${entryPath}.recordClasses" (publication.recordClasses or null);
          sourceFile = requireNonEmptyString "${entryPath}.source.sourceFile" (source.sourceFile or null);
          materializerFamily = requireNonEmptyString
            "${entryPath}.materializerFamily"
            (publication.materializerFamily or null);
          stem = safeStem scopeId;
          _source =
            if
              (source.schema or null) == "gamp-protected-reservation-set-v1"
              && (source.sourceClass or null) == "protected"
              && lib.hasPrefix "/run/secrets/" sourceFile
            then
              true
            else
              throw "diagnostic.protected-reservation-name-publication-source-invalid: NixOS DNS renderer rejected an unapproved protected source without logging address material";
          _scope =
            if
              ownerScope == scopeId
              && builtins.elem ownerScope requesterScopes
              && !(builtins.elem "*" requesterScopes)
            then
              true
            else
              throw "diagnostic.protected-reservation-name-scope-invalid: NixOS DNS renderer rejected an unscoped publication without logging address material";
          _recordClasses =
            if
              builtins.all (recordClass: builtins.elem recordClass [ "A" "AAAA" "PTR" ]) recordClasses
              && builtins.length (lib.unique recordClasses) == builtins.length recordClasses
            then
              true
            else
              throw "diagnostic.protected-reservation-name-record-class-invalid: NixOS DNS renderer rejected invalid publication classes";
          _policy =
            if
              (publication.fallbackBehavior or null) == "local-only"
              && builtins.isString (publication.publicationDenialDiagnostic or null)
              && publication.publicationDenialDiagnostic != ""
            then
              true
            else
              throw "diagnostic.protected-reservation-name-policy-invalid: NixOS DNS renderer requires fail-closed local-only publication";
          generatorUnit =
            if materializerFamily == "ipv4" then
              "gen-kea-${stem}.service"
            else if materializerFamily == "ipv6" then
              "gen-kea-dhcp6-${stem}.service"
            else
              throw "diagnostic.protected-reservation-name-materializer-family-invalid: NixOS DNS renderer requires an explicit CPM family";
        in
        builtins.seq _source (
          builtins.seq _scope (
            builtins.seq _recordClasses (
              builtins.seq _policy {
                inherit scopeId namespace recordClasses generatorUnit;
                configFile = "/run/protected-reservation-dns/${stem}.conf";
              }
            )
          )
        )
      ) (builtins.length raw);
      keys = map (publication: publication.configFile) normalized;
    in
    if builtins.length (lib.unique keys) == builtins.length keys then
      normalized
    else
      throw "diagnostic.protected-reservation-name-publication-duplicate: NixOS DNS renderer requires one materializer per protected scope";

  listenAddresses = lib.unique (
    [
      "127.0.0.1"
      "::1"
    ]
    ++ stringList (dnsService.listen or [ ])
  );

  allowFrom = lib.unique (
    [
      "127.0.0.0/8"
      "::1/128"
    ]
    ++ stringList (dnsService.allowFrom or [ ])
  );

  forwarders = dnsAuthority.rootForwarders;

  interfaces =
    if renderedModel ? interfaces && builtins.isAttrs renderedModel.interfaces then
      renderedModel.interfaces
    else
      { };

  runtimeOriginEgress =
    if builtins.isAttrs (runtimeTarget.runtimeOriginEgress or null) then
      runtimeTarget.runtimeOriginEgress
    else
      { };

  hasDnsRuntimeOriginEgress =
    (runtimeOriginEgress.enabled or false)
    && (runtimeOriginEgress.source or null) == "dns-service"
    && (
      (runtimeOriginEgress.policyRoutingRequired or false)
      || builtins.isAttrs (runtimeOriginEgress.policyRouting or null)
    );

  dnsEgressPolicy =
    if hasDnsRuntimeOriginEgress && builtins.isAttrs (runtimeOriginEgress.policyRouting or null) then
      runtimeOriginEgress.policyRouting
    else
      null;

  dnsEgressSelectedInterface =
    if
      dnsEgressPolicy != null
      && builtins.isString (dnsEgressPolicy.selectedInterface or null)
      && builtins.hasAttr dnsEgressPolicy.selectedInterface interfaces
    then
      interfaces.${dnsEgressPolicy.selectedInterface}
    else
      { };

  dnsEgressSelectedAllocation =
    if builtins.isAttrs (dnsEgressSelectedInterface.policyRoutingAllocation or null) then
      dnsEgressSelectedInterface.policyRoutingAllocation
    else
      { };

  dnsEgressPolicyComplete =
    dnsEgressPolicy != null
    && (dnsEgressPolicy.source or null) == "control-plane-model"
    && builtins.isString (dnsEgressPolicy.selectedUplink or null)
    && (runtimeOriginEgress.uplinks or [ ]) == [ dnsEgressPolicy.selectedUplink ]
    && builtins.isString (dnsEgressPolicy.selectedInterface or null)
    && (dnsEgressSelectedInterface.sourceKind or null) == "wan"
    && builtins.isString (dnsEgressPolicy.runtimeIfName or null)
    && dnsEgressPolicy.runtimeIfName != ""
    && (dnsEgressSelectedInterface.runtimeIfName or dnsEgressSelectedInterface.renderedIfName or null)
      == dnsEgressPolicy.runtimeIfName
    && (dnsEgressSelectedAllocation.source or null) == "control-plane-model"
    && builtins.isInt (dnsEgressPolicy.tableId or null)
    && dnsEgressPolicy.tableId > 0
    && (dnsEgressSelectedAllocation.tableId or null) == dnsEgressPolicy.tableId
    && builtins.isInt (dnsEgressPolicy.rulePriority or null)
    && dnsEgressPolicy.rulePriority > 0
    && (dnsEgressSelectedAllocation.tableRulePriority or null) == dnsEgressPolicy.rulePriority
    && builtins.isInt (dnsEgressPolicy.firewallMark or null)
    && dnsEgressPolicy.firewallMark > 0;

  validationAuthority =
    if builtins.isAttrs (dnsService.validationAuthority or null) then
      dnsService.validationAuthority
    else
      null;

  validationAuthorityComplete =
    validationAuthority == null
    || (
      dnsAuthority.recursionMode == "iterative"
      && (validationAuthority.kind or null) == "controlled-iterative-hierarchy"
      && (validationAuthority.scope or null) == "harness"
      && builtins.isString (validationAuthority.selectedUplink or null)
      && validationAuthority.selectedUplink != ""
      && dnsEgressPolicy != null
      && (dnsEgressPolicy.selectedUplink or null) == validationAuthority.selectedUplink
      && (validationAuthority.trust.mode or null) == "insecure-controlled-root"
    );

  explicitDnsForwardPairs =
    lib.filter
      (pair:
        builtins.isAttrs pair
        && (pair.action or "accept") == "accept"
        && (pair.trafficType or null) == "dns"
        && builtins.isList (pair."in" or null))
      (forwardingIntent.normalizedExplicitForwardPairs or [ ]);

  explicitDnsServiceEgressPairs =
    lib.filter
      (pair:
        builtins.isAttrs pair
        && (pair.action or "accept") == "accept"
        && (pair.trafficType or null) == "dns"
        && builtins.isList (pair."in" or null)
        && builtins.isList (pair."out" or null)
        && builtins.isList (pair.sourcePrefixes or null)
        && pair.sourcePrefixes != [ ])
      (forwardingIntent.normalizedExplicitForwardPairs or [ ]);

  sourcePrefixRecord = value:
    let
      prefix =
        if builtins.isString value then
          value
        else if builtins.isAttrs value && builtins.isString (value.prefix or null) then
          value.prefix
        else
          "";
      family =
        if builtins.isAttrs value && (value.family or null) == 6 then
          6
        else if builtins.isString prefix && lib.hasInfix ":" prefix then
          6
        else
          4;
    in
    if prefix == "" then null else { inherit prefix family; };

  dnsServiceForwardEgressRules =
    lib.concatMap
      (pair:
        lib.concatMap
          (source:
            lib.concatMap
              (inIf:
                map
                  (outIf: {
                    inherit source;
                    inInterface = inIf;
                    outInterface = outIf;
                  })
                  (stringList (pair."out" or [ ])))
              (stringList (pair."in" or [ ])))
          (lib.filter (value: value != null) (map sourcePrefixRecord (asList (pair.sourcePrefixes or [ ])))))
      explicitDnsServiceEgressPairs;

  hasExplicitDnsAllowFrom =
    ifName:
    builtins.any (pair: builtins.elem ifName (pair."in" or [ ])) explicitDnsForwardPairs;

  directEgressBlockedTenants =
    if dnsService ? directEgressBlockedTenants && builtins.isList dnsService.directEgressBlockedTenants then
      lib.filter builtins.isString dnsService.directEgressBlockedTenants
    else
      null;

  shouldBlockInterface =
    ifName: iface:
    let
      sourceKind = iface.sourceKind or "";
      tenant = iface.tenant or null;
    in
    if sourceKind == "wan" || sourceKind == "overlay" then
      false
    else if directEgressBlockedTenants != null then
      sourceKind == "tenant" && builtins.isString tenant && builtins.elem tenant directEgressBlockedTenants
    else
      true;
in
if !(builtins.isAttrs dnsService) then
  null
else
  let
    _fwd = dnsAuthority.rootForwarders;
    _listen = lib.unique ([ "127.0.0.1" "::1" ] ++ stringList (dnsService.listen or [ ]));
    _nonLoopback = builtins.filter (a: a != "127.0.0.1" && a != "::1") _listen;
    _selfRef = builtins.filter (f: builtins.elem f _nonLoopback) _fwd;
  in
  if _selfRef != [ ] then
    throw "NixOS DNS renderer DNS_RENDERER_CONTRACT_DIVERGENCE: self-referential forwarder rejected without logging address material; GAMP: FS-540-HDS-010-SDS-010-SMS-035"
  else if hasDnsRuntimeOriginEgress && !dnsEgressPolicyComplete then
    throw "NixOS DNS renderer DNS_RENDERER_CONTRACT_DIVERGENCE: CPM DNS runtime-origin egress lacks one complete model-owned policy-routing selection; address material is intentionally omitted; GAMP: FS-540-HDS-010-SDS-010-SMS-035"
  else if !validationAuthorityComplete then
    throw "NixOS DNS renderer DNS_VALIDATION_AUTHORITY_EXTERNAL: controlled iterative authority is missing its harness scope or disagrees with the selected model-owned egress; address material is intentionally omitted; GAMP: FS-540-HDS-010-SDS-010-SMS-045"
  else
  rec {
    inherit dnsService listenAddresses allowFrom forwarders interfaces dnsServiceForwardEgressRules dnsEgressPolicy validationAuthority protectedReservationPublications;
    inherit (dnsAuthority)
      recursionMode
      reproducibilityWarnings
      warningCodes
      localForwardZones
      requesterPolicies
      localOnlyPolicy
      ;
    listen4 = lib.filter (value: builtins.isString value && lib.hasInfix "." value) listenAddresses;
    listen6 = lib.filter (value: builtins.isString value && lib.hasInfix ":" value) listenAddresses;
    forwarder4 = lib.filter (value: builtins.isString value && lib.hasInfix "." value) forwarders;
    forwarder6 = lib.filter (value: builtins.isString value && lib.hasInfix ":" value) forwarders;
    hasMixedForwarders = forwarder4 != [ ] && forwarder6 != [ ];
    deniedResolverCidrs = stringList (dnsService.deniedResolverCidrs or [ ]);
    deniedResolverCidrs4 = lib.filter (value: builtins.isString value && lib.hasInfix "." value) deniedResolverCidrs;
    deniedResolverCidrs6 = lib.filter (value: builtins.isString value && lib.hasInfix ":" value) deniedResolverCidrs;
    publicResolverForwardIngressNames =
      if ((dnsService.killSwitch or { }).blockPublicResolvers or false) then
        lib.unique
          (
            lib.filter (name: name != "") (
              map
                (
                  ifName:
                  let
                    iface = interfaces.${ifName} or { };
                    sourceKind = iface.sourceKind or "";
                    renderedName =
                      if iface ? renderedIfName && builtins.isString iface.renderedIfName && iface.renderedIfName != "" then
                        iface.renderedIfName
                      else if iface ? interfaceName && builtins.isString iface.interfaceName && iface.interfaceName != "" then
                        iface.interfaceName
                      else
                        ifName;
                  in
                  if sourceKind == "wan" || sourceKind == "overlay" then "" else renderedName
                )
                (builtins.attrNames interfaces)
            )
          )
      else
        [ ];
    localZones =
      lib.filter
        (zone: builtins.isAttrs zone && builtins.isString (zone.name or null) && zone.name != "")
        (if builtins.isList (dnsService.localZones or null) then dnsService.localZones else [ ]);
    localRecords =
      lib.filter
        (record: builtins.isAttrs record && builtins.isString (record.name or null) && record.name != "")
        (if builtins.isList (dnsService.localRecords or null) then dnsService.localRecords else [ ]);
  namespaceFallback =
    if builtins.isAttrs (dnsService.namespaceFallback or null) then dnsService.namespaceFallback else { };
  namespaceFallbackDecisionsRaw =
    if builtins.isList (namespaceFallback.decisions or null) then namespaceFallback.decisions else [ ];
  invalidNamespaceConflictDecisions =
    lib.filter
      (decision:
        builtins.isAttrs decision
        && !(decision.publicRecursionFallback or false)
        && builtins.elem (decision.action or null) [ "block" "deny" ]
        && !(
          builtins.isString (decision.requesterScope or null)
          && decision.requesterScope != ""
          && builtins.isString (decision.namespace or null)
          && decision.namespace != ""
        ))
      namespaceFallbackDecisionsRaw;
  namespaceFallbackDecisions =
      if invalidNamespaceConflictDecisions != [ ] then
        let
          bad = builtins.head invalidNamespaceConflictDecisions;
          badNamespace =
            if builtins.isString (bad.namespace or null) && bad.namespace != "" then
              bad.namespace
            else
              "<missing-namespace>";
          badAction =
            if builtins.isString (bad.action or null) && bad.action != "" then
              bad.action
            else
              "<missing-action>";
        in
        throw "NixOS DNS renderer requires requesterScope and namespace for modeled namespace-conflict state predicate action '${badAction}' on '${badNamespace}'"
      else
      lib.filter
        (decision:
          builtins.isAttrs decision
          && builtins.isString (decision.requesterScope or null)
          && decision.requesterScope != ""
          && builtins.isString (decision.namespace or null)
          && decision.namespace != ""
          && !((decision.publicRecursionFallback or false))
          && builtins.elem (decision.action or null) [ "block" "deny" ])
        namespaceFallbackDecisionsRaw;
    dnsRoles = if builtins.isAttrs (dnsService.roles or null) then dnsService.roles else { };
    recursionRole = if builtins.isAttrs (dnsRoles.recursion or null) then dnsRoles.recursion else { };
    roleOutgoingInterfaces = stringList (recursionRole.outgoingInterfaces or [ ]);
    outgoingInterfaces = lib.unique (if roleOutgoingInterfaces != [ ] then roleOutgoingInterfaces else stringList (dnsService.outgoingInterfaces or [ ]));
    dnsEgressSources = if outgoingInterfaces != [ ] then outgoingInterfaces else listenAddresses;
    dnsEgressSources4 = lib.filter (value: builtins.isString value && lib.hasInfix "." value) dnsEgressSources;
    dnsEgressSources6 = lib.filter (value: builtins.isString value && lib.hasInfix ":" value) dnsEgressSources;
    ingressInterfaceNames =
      if dnsService.blockDirectEgress or false then
        lib.unique
          (
            lib.filter (name: name != "") (
              map
                (
                  ifName:
                  let
                    iface = interfaces.${ifName} or { };
                  in
                  if !(shouldBlockInterface ifName iface) then
                    ""
                  else if iface ? renderedIfName && builtins.isString iface.renderedIfName && iface.renderedIfName != "" then
                    if hasExplicitDnsAllowFrom iface.renderedIfName then "" else iface.renderedIfName
                  else if iface ? interfaceName && builtins.isString iface.interfaceName && iface.interfaceName != "" then
                    if hasExplicitDnsAllowFrom iface.interfaceName then "" else iface.interfaceName
                  else if hasExplicitDnsAllowFrom ifName then
                    ""
                  else
                    ifName
                )
                (builtins.attrNames interfaces)
            )
          )
      else
        [ ];
  }
