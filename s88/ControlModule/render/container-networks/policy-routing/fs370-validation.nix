{ lib, common }:

let
  peers = import ./peers.nix { inherit lib common; };

  attrsOrEmpty = value: if builtins.isAttrs value then value else { };
  listOrEmpty = value: if builtins.isList value then value else [ ];

  stringOrNull =
    value:
    if builtins.isString value && value != "" then value else null;

  prefixFamily =
    prefix:
    if builtins.isAttrs prefix && builtins.isInt (prefix.family or null) then
      prefix.family
    else if builtins.isString (prefix.prefix or null) && lib.hasInfix ":" prefix.prefix then
      6
    else
      4;

  prefixValue =
    value:
    if builtins.isString value then
      value
    else if builtins.isAttrs value && builtins.isString (value.prefix or null) then
      value.prefix
    else if builtins.isAttrs value && builtins.isString (value.dst or null) then
      value.dst
    else
      null;

  interfaceKeysFor =
    byInterface: interfaceName:
    lib.filter
      (name: name == interfaceName || lib.hasSuffix "-${interfaceName}" name)
      (builtins.attrNames byInterface);

  entriesForInterface =
    byInterface: interfaceName:
    lib.concatMap (name: listOrEmpty byInterface.${name}) (interfaceKeysFor byInterface interfaceName);

  indexedEntries =
    byInterface:
    lib.concatLists (
      lib.mapAttrsToList
        (name: entries: map (entry: entry // { _s88OutputInterface = name; }) (listOrEmpty entries))
        byInterface
    );

  normalizeRulesByRenderedInterface =
    renderedInterfaceNames: rulesByInterface:
    builtins.listToAttrs (
      lib.mapAttrsToList
        (ifName: rules: {
          name = renderedInterfaceNames.${ifName} or ifName;
          value = listOrEmpty rules;
        })
        (attrsOrEmpty rulesByInterface)
    );

  normalizeRoutesByRenderedInterface =
    renderedInterfaceNames: routesByInterface:
    builtins.listToAttrs (
      lib.mapAttrsToList
        (ifName: routes: {
          name = renderedInterfaceNames.${ifName} or ifName;
          value = listOrEmpty routes;
        })
        (attrsOrEmpty routesByInterface)
    );

  addressForFamily =
    family: iface:
    let
      fromAddresses = peers.addressForFamily family iface;
      fromFlatField =
        if family == 6 then
          common.stripCidr (iface.addr6 or null)
        else
          common.stripCidr (iface.addr4 or null);
    in
    if fromAddresses != null then fromAddresses else fromFlatField;

  gatewayForPrefix =
    iface: prefix:
    let
      family = prefixFamily prefix;
      address = addressForFamily family iface;
    in
    if family == 6 then peers.ipv6PeerFor127 address else peers.ipv4PeerFor31 address;

  hasMaterializedRule =
    rulesByInterface: lane: prefix:
    builtins.any
      (
        rule:
        (rule.To or null) == prefix.prefix
        && (rule.IncomingInterface or null) == lane.policyInterface
        && (rule.Table or null) != 254
      )
      (lib.concatLists (builtins.attrValues (attrsOrEmpty rulesByInterface)));

  hasMaterializedRoute =
    routesByInterface: lane: prefix:
    builtins.any
      (
        route:
        (route.Destination or null) == prefix.prefix
        && ((prefix.gateway or null) == null || (route.Gateway or null) == prefix.gateway)
      )
      (entriesForInterface routesByInterface lane.accessInterface);

  actualRouteFor =
    routesByInterface: prefix:
    let
      matches = lib.filter (route: (route.Destination or null) == prefix.prefix) (indexedEntries routesByInterface);
    in
    if matches == [ ] then null else builtins.head matches;

  reverseRulePresent =
    ruleset: lane:
    builtins.isString ruleset
    && lib.hasInfix "iifname \"${lane.policyInterface}\" oifname \"${lane.accessInterface}\"" ruleset
    && lib.hasInfix "accept comment \"${lane.comment}\"" ruleset;

  forceChecks =
    checks:
    builtins.foldl' (ok: check: builtins.seq check ok) true checks;

  interfaceKeyForRenderedName =
    renderedInterfaceNames: renderedName:
    lib.findFirst
      (name: (renderedInterfaceNames.${name} or null) == renderedName)
      null
      (builtins.attrNames renderedInterfaceNames);

  accessUnitForRenderedName =
    interfaces: renderedInterfaceNames: renderedName:
    let
      key = interfaceKeyForRenderedName renderedInterfaceNames renderedName;
      iface = if key == null then { } else attrsOrEmpty interfaces.${key};
      lane = attrsOrEmpty ((attrsOrEmpty (iface.backingRef or null)).lane or null);
    in
    stringOrNull (lane.access or null);

  prefixesForAccessUnit =
    tenantPrefixOwners: accessUnit:
    let
      ownerEntries = lib.filter
        (
          owner:
          builtins.isAttrs owner
          && (owner.owner or null) == accessUnit
          && prefixValue owner != null
        )
        (builtins.attrValues tenantPrefixOwners);
    in
    map
      (owner: {
        family = if builtins.isInt (owner.family or null) then owner.family else if lib.hasInfix ":" (prefixValue owner) then 6 else 4;
        prefix = prefixValue owner;
      })
      ownerEntries;

  explicitReversePairs =
    forwardingIntent:
    lib.filter
      (
        pair:
        builtins.isAttrs pair
        && (pair.action or "accept") == "accept"
        && builtins.isString (pair.comment or null)
        && lib.hasInfix "selector-handoff-reverse" pair.comment
        && !(lib.hasInfix "runtime-origin" pair.comment)
      )
      (listOrEmpty ((attrsOrEmpty forwardingIntent).normalizedExplicitForwardPairs or null));
in
rec {
  validateMaterializedArtifacts =
    { traceId ? "FS-370-HDS-010-SDS-010-SMS-120"
    , nodeName ? "unknown"
    , expectedLanes ? [ ]
    , rulesByInterface ? { }
    , routesByInterface ? { }
    , ruleset ? null
    ,
    }:
    let
      flatRules = lib.concatLists (builtins.attrValues (attrsOrEmpty rulesByInterface));
      catchAllRules = lib.filter
        (
          rule:
          (rule.To or null) == "0.0.0.0/0"
          || (rule.To or null) == "::/0"
        )
        flatRules;
      routeFailureFor =
        lane: prefix:
        let
          actual = actualRouteFor routesByInterface prefix;
          actualText =
            if actual == null then
              "missing"
            else
              "${actual._s88OutputInterface or "unknown"} via ${actual.Gateway or "none"}";
        in
        throw "${traceId}: return-path route wrong-interface diagnostic for ${nodeName} lane ${lane.lane}: prefix ${prefix.prefix} expected interface ${lane.accessInterface} via ${prefix.gateway or "any"}, actual ${actualText}";
    in
    forceChecks (
      [
        (
          if catchAllRules == [ ] then
            true
          else
            throw "${traceId}: prohibited-default-route diagnostic for ${nodeName}: policy rule uses To=${(builtins.head catchAllRules).To or "unknown"} on ${((builtins.head catchAllRules).IncomingInterface or "unknown")}"
        )
        (
          if !(builtins.isString ruleset) || !(lib.hasInfix "selector-handoff" ruleset) || !(lib.hasInfix "no-uplink" ruleset) then
            true
          else
            throw "${traceId}: wrong-comment diagnostic for ${nodeName}: selector handoff nft comment collapsed to no-uplink"
        )
      ]
      ++ lib.concatMap
        (
          lane:
          [
            (
              if ruleset == null || reverseRulePresent ruleset lane then
                true
              else
                throw "${traceId}: missing reverse accept rule diagnostic for ${nodeName} lane ${lane.lane}: expected iifname ${lane.policyInterface} oifname ${lane.accessInterface} comment ${lane.comment}"
            )
          ]
          ++ map
            (
              prefix:
              if hasMaterializedRule rulesByInterface lane prefix then
                true
              else
                throw "${traceId}: missing per-lane ip rule diagnostic for ${nodeName} lane ${lane.lane}: To=${prefix.prefix} iif=${lane.policyInterface}"
            )
            (lane.prefixes or [ ])
          ++ map
            (
              prefix:
              if hasMaterializedRoute routesByInterface lane prefix then
                true
              else
                routeFailureFor lane prefix
            )
            (lane.prefixes or [ ])
        )
        expectedLanes
    );

  expectedLanesFromContainer =
    { containerModel
    , interfaces
    , renderedInterfaceNames
    , forwardingIntent ? null
    , isExpectedPolicyInterface ? (_: true)
    , isExpectedAccessInterface ? (_: true)
    ,
    }:
    let
      tenantPrefixOwners = attrsOrEmpty ((attrsOrEmpty (containerModel.site or null)).tenantPrefixOwners or null);
      laneForPair =
        pair:
        lib.concatMap
          (
            policyInterface:
            lib.concatMap
              (
                accessInterface:
                let
                  accessKey = interfaceKeyForRenderedName renderedInterfaceNames accessInterface;
                  accessIface = if accessKey == null then { } else attrsOrEmpty interfaces.${accessKey};
                  accessUnit = accessUnitForRenderedName interfaces renderedInterfaceNames accessInterface;
                  basePrefixes =
                    if accessUnit == null then
                      [ ]
                    else
                      prefixesForAccessUnit tenantPrefixOwners accessUnit;
                  prefixes = map
                    (prefix: prefix // { gateway = gatewayForPrefix accessIface prefix; })
                    basePrefixes;
                in
                lib.optional
                  (
                    prefixes != [ ]
                    && isExpectedPolicyInterface policyInterface
                    && isExpectedAccessInterface accessInterface
                  )
                  {
                  lane = if accessUnit == null then accessInterface else accessUnit;
                  inherit
                    policyInterface
                    accessInterface
                    prefixes
                    ;
                  comment = pair.comment;
                }
              )
              (listOrEmpty (pair."out" or null))
          )
          (listOrEmpty (pair."in" or null));
    in
    lib.concatMap laneForPair (explicitReversePairs forwardingIntent);

  validateContainer =
    { nodeName ? null
    , containerModel
    , interfaces
    , renderedInterfaceNames
    , forwardingIntent ? null
    , isExpectedPolicyInterface ? (_: true)
    , isExpectedAccessInterface ? (_: true)
    , policyRoutingByInterface
    , firewallRuleset ? null
    ,
    }:
    let
      resolvedNodeName =
        if nodeName != null then
          nodeName
        else
          containerModel.unitName or containerModel.containerName or "unknown";
      expectedLanes = expectedLanesFromContainer {
        inherit
          containerModel
          interfaces
          renderedInterfaceNames
          forwardingIntent
          isExpectedPolicyInterface
          isExpectedAccessInterface
          ;
      };
    in
    validateMaterializedArtifacts {
      nodeName = resolvedNodeName;
      inherit expectedLanes;
      ruleset = firewallRuleset;
      rulesByInterface = normalizeRulesByRenderedInterface renderedInterfaceNames (
        policyRoutingByInterface.rules or { }
      );
      routesByInterface = normalizeRoutesByRenderedInterface renderedInterfaceNames (
        policyRoutingByInterface.routes or { }
      );
    };
}
