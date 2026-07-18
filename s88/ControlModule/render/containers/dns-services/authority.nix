{ lib, dnsService }:

let
  stringList = value:
    if builtins.isList value then lib.filter builtins.isString value else [ ];

  attrsList = value:
    if builtins.isList value then lib.filter builtins.isAttrs value else [ ];

  sortedUnique = values:
    lib.sort builtins.lessThan (lib.unique values);

  sameStrings = left: right:
    sortedUnique left == sortedUnique right;

  hasIpv4 = values:
    builtins.any (value: builtins.isString value && lib.hasInfix "." value) values;

  hasIpv6 = values:
    builtins.any (value: builtins.isString value && lib.hasInfix ":" value) values;

  familyComplete = values:
    hasIpv4 values && hasIpv6 values;

  fail = code: reason:
    throw "network-renderer-nixos DNS ${code}: ${reason}; address material is intentionally omitted";

  recursionMode =
    if !(dnsService ? recursionMode) then
      null
    else if builtins.elem dnsService.recursionMode [ "iterative" "forwarding" "local-only" ] then
      dnsService.recursionMode
    else
      fail "DNS_RECURSION_MODE_INVALID" "CPM emitted an unsupported recursion mode";

  reproducibilityWarnings = attrsList (dnsService.reproducibilityWarnings or [ ]);
  warningCodes = sortedUnique (
    map (warning: warning.code) (
      lib.filter
        (warning: builtins.isString (warning.code or null) && warning.code != "")
        reproducibilityWarnings
    )
  );
  fatalWarningCodes = builtins.filter
    (code: code != "DNS_CORE_UPSTREAM_HARDCODED")
    warningCodes;

  legacyForwarders =
    if dnsService ? forwarders then
      stringList dnsService.forwarders
    else if dnsService ? upstreams then
      stringList dnsService.upstreams
    else
      [ ];

  upstreamResolvers = attrsList (dnsService.upstreamResolvers or [ ]);
  namedCoreResolvers = builtins.filter
    (resolver: (resolver.kind or null) == "named-core-resolver")
    upstreamResolvers;
  validNamedCoreResolver = resolver:
    let
      endpointAuthority =
        if builtins.isAttrs (resolver.endpointAuthority or null) then
          resolver.endpointAuthority
        else
          { };
    in
    builtins.isString (endpointAuthority.relationId or null)
    && endpointAuthority.relationId != ""
    && builtins.isString (endpointAuthority.terminalAttachmentId or null)
    && endpointAuthority.terminalAttachmentId != "";
  namedCoreAddresses = sortedUnique (
    lib.concatMap (resolver: stringList (resolver.addresses or [ ])) namedCoreResolvers
  );

  serviceEndpointBindings = attrsList (dnsService.serviceEndpointBindings or [ ]);
  validServiceEndpointBinding = binding:
    builtins.isString (binding.service or null)
    && binding.service != ""
    && builtins.isString (binding.requesterService or null)
    && binding.requesterService != ""
    && builtins.isString (binding.providerNode or null)
    && binding.providerNode != ""
    && builtins.isString (binding.relationId or null)
    && binding.relationId != ""
    && builtins.isString (binding.terminalAttachmentId or null)
    && binding.terminalAttachmentId != ""
    && familyComplete (stringList (binding.addresses or [ ]));
  serviceEndpointAddresses = sortedUnique (
    lib.concatMap (binding: stringList (binding.addresses or [ ])) serviceEndpointBindings
  );
  configuredListenAddresses = sortedUnique (stringList (dnsService.listen or [ ]));

  localAuthorityResolvers = builtins.filter
    (resolver: (resolver.kind or null) == "local-namespace-authority")
    upstreamResolvers;

  localForwardZones = attrsList (dnsService.localForwardZones or [ ]);
  validLocalForwardZone = zone:
    builtins.isString (zone.name or null)
    && zone.name != ""
    && builtins.isString (zone.relationId or null)
    && zone.relationId != ""
    && (zone.forwardFirst or true) == false
    && familyComplete (stringList (zone.forwardTo or [ ]));

  localZones = attrsList (dnsService.localZones or [ ]);
  shadowedLocalNamespaces = map (zone: zone.name) (
    builtins.filter
      (zone:
        builtins.isString (zone.name or null)
        && zone.name != ""
        && builtins.any (forwardZone: (forwardZone.name or null) == zone.name) localForwardZones
        && (zone.type or "static") != "transparent")
      localZones
  );

  requesterPolicies = attrsList (dnsService.requesterPolicies or [ ]);
  validRequesterPolicy = policy:
    (policy.action or null) == "refuse_non_local"
    && builtins.isString (policy.requesterService or null)
    && policy.requesterService != ""
    && builtins.isString (policy.relationId or null)
    && policy.relationId != ""
    && stringList (policy.sourcePrefixes or [ ]) != [ ]
    && stringList (policy.namespaces or [ ]) != [ ];

  localOnlyPolicy =
    if builtins.isAttrs (dnsService.localOnlyPolicy or null) then
      dnsService.localOnlyPolicy
    else
      { };
  validLocalOnlyPolicy =
    localOnlyPolicy != { }
    && builtins.isString (localOnlyPolicy.providerService or null)
    && localOnlyPolicy.providerService != ""
    && builtins.isString (localOnlyPolicy.relationId or null)
    && localOnlyPolicy.relationId != ""
    && stringList (localOnlyPolicy.namespaces or [ ]) != [ ]
    && (localOnlyPolicy.recursion or true) == false
    && (localOnlyPolicy.publicFallback or true) == false
    && (localOnlyPolicy.transitiveEgress or true) == false
    && (localOnlyPolicy.missAction or null) == "refuse";

  _fatalWarnings =
    if fatalWarningCodes == [ ] then
      true
    else
      fail
        (builtins.concatStringsSep "," fatalWarningCodes)
        "CPM marked this resolver contract non-reproducible";

  _modeContract =
    if recursionMode == "forwarding" then
      if
        builtins.length namedCoreResolvers == 1
        && builtins.all validNamedCoreResolver namedCoreResolvers
        && familyComplete namedCoreAddresses
        && (legacyForwarders == [ ] || sameStrings legacyForwarders namedCoreAddresses)
      then
        true
      else
        fail
          "DNS_RENDERER_CONTRACT_DIVERGENCE"
          "forwarding mode lacks one dual-stack named-core resolver or disagrees with the legacy projection"
    else if recursionMode == "iterative" then
      if legacyForwarders == [ ] && namedCoreResolvers == [ ] then
        true
      else
        fail
          "DNS_RECURSION_MODE_INVALID"
          "iterative mode contains a forwarding or fallback source"
    else if recursionMode == "local-only" then
      if
        legacyForwarders == [ ]
        && builtins.length localAuthorityResolvers == 1
        && localForwardZones != [ ]
        && builtins.all validLocalForwardZone localForwardZones
        && validLocalOnlyPolicy
      then
        true
      else
        fail
          "DNS_LOCAL_ONLY_AUTHORITY_LEAK"
          "local-only mode is incomplete or would permit recursion, fallback, or transitive egress"
    else
      true;

  _serviceEndpointContract =
    if serviceEndpointBindings == [ ] then
      true
    else if
      builtins.all validServiceEndpointBinding serviceEndpointBindings
      && sameStrings serviceEndpointAddresses configuredListenAddresses
    then
      true
    else
      fail
        "DNS_RENDERER_CONTRACT_DIVERGENCE"
        "provider listener addresses or terminal authority disagree with the CPM service endpoint binding";

  _namespaceShadowContract =
    if shadowedLocalNamespaces == [ ] then
      true
    else
      fail
        "DNS_LOCAL_NAMESPACE_SHADOWED"
        "a local zone would terminate a namespace before its modeled forwarding authority";

  _requesterPolicyContract =
    if builtins.all validRequesterPolicy requesterPolicies then
      true
    else
      fail
        "DNS_LOCAL_ONLY_AUTHORITY_LEAK"
        "a provider requester policy is not source-scoped refuse_non_local";

  rootForwarders =
    if recursionMode == "forwarding" then
      namedCoreAddresses
    else if recursionMode == null then
      legacyForwarders
    else
      [ ];
in
builtins.seq _fatalWarnings (
  builtins.seq _modeContract (
    builtins.seq _serviceEndpointContract (
      builtins.seq _namespaceShadowContract (
        builtins.seq _requesterPolicyContract {
          inherit
            recursionMode
            reproducibilityWarnings
            warningCodes
            rootForwarders
            localForwardZones
            requesterPolicies
            localOnlyPolicy
            ;
        }
      )
    )
  )
)
