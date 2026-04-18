{
  lib,
  runtimeTarget ? { },
  interfaces ? { },
  wanIfs ? [ ],
  lanIfs ? [ ],
  uplinks ? { },
}:

let
  asList =
    value:
    if value == null then
      [ ]
    else if builtins.isList value then
      value
    else
      [ value ];

  asStringList = value: lib.filter builtins.isString (asList value);

  sortedStrings =
    values:
    lib.sort builtins.lessThan (
      lib.unique (lib.filter (value: builtins.isString value && value != "") values)
    );

  boolOrFalse = value: if builtins.isBool value then value else false;

  attrPathOrNull =
    attrs: path:
    if path == [ ] then
      attrs
    else if !builtins.isAttrs attrs then
      null
    else
      let
        key = builtins.head path;
        rest = builtins.tail path;
      in
      if builtins.hasAttr key attrs then attrPathOrNull attrs.${key} rest else null;

  valuesFromPaths =
    {
      roots,
      paths,
    }:
    lib.concatMap (
      path:
      lib.concatMap (
        root:
        let
          value = attrPathOrNull root path;
        in
        if value == null then [ ] else [ value ]
      ) roots
    ) paths;

  boolLikeValuesFromPaths =
    {
      roots,
      paths,
    }:
    lib.concatMap
      (
        value:
        if builtins.isBool value then
          [ value ]
        else if builtins.isAttrs value && value ? enable && builtins.isBool value.enable then
          [ value.enable ]
        else
          [ ]
      )
      (valuesFromPaths {
        inherit roots paths;
      });

  boolLikeFromPaths =
    {
      roots,
      paths,
    }:
    let
      values = boolLikeValuesFromPaths { inherit roots paths; };
    in
    if values == [ ] then null else builtins.head values;

  firstAttrsFromPaths =
    {
      roots,
      paths,
    }:
    let
      values = lib.filter builtins.isAttrs (valuesFromPaths {
        inherit roots paths;
      });
    in
    if values == [ ] then { } else builtins.head values;

  stringListFromPaths =
    {
      roots,
      paths,
    }:
    sortedStrings (
      lib.concatMap asStringList (valuesFromPaths {
        inherit roots paths;
      })
    );

  lastStringSegment =
    separator: value:
    let
      parts = lib.splitString separator value;
      count = builtins.length parts;
    in
    if count == 0 then null else builtins.elemAt parts (count - 1);

  attrOr =
    attrs: name: fallback:
    if builtins.isAttrs attrs && builtins.hasAttr name attrs then attrs.${name} else fallback;

  actualNameForInterface =
    ifName: iface:
    if
      iface ? containerInterfaceName
      && builtins.isString iface.containerInterfaceName
      && iface.containerInterfaceName != ""
    then
      iface.containerInterfaceName
    else if
      iface ? interfaceName && builtins.isString iface.interfaceName && iface.interfaceName != ""
    then
      iface.interfaceName
    else if
      iface ? hostInterfaceName
      && builtins.isString iface.hostInterfaceName
      && iface.hostInterfaceName != ""
    then
      iface.hostInterfaceName
    else if
      iface ? renderedIfName && builtins.isString iface.renderedIfName && iface.renderedIfName != ""
    then
      iface.renderedIfName
    else if iface ? ifName && builtins.isString iface.ifName && iface.ifName != "" then
      iface.ifName
    else
      ifName;

  semanticInterfaceFor =
    iface:
    if iface ? semanticInterface && builtins.isAttrs iface.semanticInterface then
      iface.semanticInterface
    else if iface ? semantic && builtins.isAttrs iface.semantic then
      iface.semantic
    else
      { };

  sourceKindForInterface =
    iface: semanticInterface:
    if semanticInterface ? kind && builtins.isString semanticInterface.kind then
      semanticInterface.kind
    else if iface ? sourceKind && builtins.isString iface.sourceKind then
      iface.sourceKind
    else if
      iface ? connectivity
      && builtins.isAttrs iface.connectivity
      && iface.connectivity ? sourceKind
      && builtins.isString iface.connectivity.sourceKind
    then
      iface.connectivity.sourceKind
    else
      null;

  rawInterfaceEntries = map (
    ifName:
    let
      iface = interfaces.${ifName};
      semanticInterface = semanticInterfaceFor iface;

      backingRef =
        if iface ? backingRef && builtins.isAttrs iface.backingRef then iface.backingRef else { };

      backingRefIdTail =
        if backingRef ? id && builtins.isString backingRef.id then
          lastStringSegment "::" backingRef.id
        else
          null;
    in
    {
      key = ifName;
      name = actualNameForInterface ifName iface;
      inherit iface semanticInterface backingRef;
      sourceKind = sourceKindForInterface iface semanticInterface;
      refs = sortedStrings [
        ifName
        (actualNameForInterface ifName iface)
        (iface.renderedIfName or null)
        (iface.interfaceName or null)
        (iface.containerInterfaceName or null)
        (iface.hostInterfaceName or null)
        (iface.ifName or null)
        (iface.sourceInterface or null)
        (
          if
            iface ? connectivity
            && builtins.isAttrs iface.connectivity
            && iface.connectivity ? upstream
            && builtins.isString iface.connectivity.upstream
          then
            iface.connectivity.upstream
          else
            null
        )
        (backingRef.name or null)
        backingRefIdTail
        (backingRef.kind or null)
      ];
    }
  ) (lib.sort builtins.lessThan (builtins.attrNames interfaces));

  interfaceEntries = map (
    entry:
    let
      roots = [
        entry.iface
        entry.semanticInterface
      ];

      explicitLocalAdapter = boolLikeFromPaths {
        inherit roots;
        paths = [
          [ "localAdapter" ]
          [ "local" ]
          [ "tenantFacing" ]
          [
            "forwarding"
            "localAdapter"
          ]
          [
            "forwarding"
            "participation"
            "localAdapter"
          ]
          [
            "forwarding"
            "traversal"
            "localAdapter"
          ]
          [
            "roles"
            "localAdapter"
          ]
          [
            "roles"
            "tenantFacing"
          ]
        ];
      };

      explicitUplink = boolLikeFromPaths {
        inherit roots;
        paths = [
          [ "uplink" ]
          [ "upstream" ]
          [
            "forwarding"
            "uplink"
          ]
          [
            "forwarding"
            "participation"
            "uplink"
          ]
          [
            "roles"
            "uplink"
          ]
          [
            "roles"
            "upstream"
          ]
          [
            "roles"
            "wan"
          ]
        ];
      };

      explicitTransit = boolLikeFromPaths {
        inherit roots;
        paths = [
          [ "transit" ]
          [
            "forwarding"
            "transit"
          ]
          [
            "forwarding"
            "participation"
            "transit"
          ]
          [
            "forwarding"
            "participatesInTraversal"
          ]
          [
            "roles"
            "transit"
          ]
        ];
      };

      explicitExitEligible = boolLikeFromPaths {
        inherit roots;
        paths = [
          [ "exitEligible" ]
          [
            "egress"
            "exitEligible"
          ]
          [
            "egress"
            "upstreamSelectionEligible"
          ]
          [
            "forwarding"
            "exitEligible"
          ]
        ];
      };

      explicitNatEnabled = boolLikeFromPaths {
        inherit roots;
        paths = [
          [ "nat" ]
          [
            "nat"
            "enable"
          ]
          [ "masquerade" ]
          [
            "masquerade"
            "enable"
          ]
          [
            "egress"
            "nat"
          ]
          [
            "egress"
            "nat"
            "enable"
          ]
          [
            "egress"
            "masquerade"
          ]
          [
            "egress"
            "masquerade"
            "enable"
          ]
        ];
      };

      explicitClampMss = boolLikeFromPaths {
        inherit roots;
        paths = [
          [ "clampMss" ]
          [ "tcpMssClamp" ]
          [
            "egress"
            "clampMss"
          ]
          [
            "egress"
            "tcpMssClamp"
          ]
        ];
      };

      explicitWan = boolLikeFromPaths {
        inherit roots;
        paths = [
          [ "wan" ]
          [
            "roles"
            "wan"
          ]
        ];
      };
    in
    entry
    // {
      explicit = {
        inherit
          explicitLocalAdapter
          explicitUplink
          explicitTransit
          explicitExitEligible
          explicitNatEnabled
          explicitClampMss
          explicitWan
          ;
      };
    }
  ) rawInterfaceEntries;

  interfaceNames = sortedStrings (map (entry: entry.name) interfaceEntries);

  namesForInterfaceToken =
    token:
    sortedStrings (
      map (entry: entry.name) (lib.filter (entry: builtins.elem token entry.refs) interfaceEntries)
    );

  resolveInterfaceTokens =
    tokens:
    sortedStrings (
      lib.concatMap (
        token:
        let
          matches = namesForInterfaceToken token;
        in
        if matches != [ ] then matches else [ token ]
      ) (asStringList tokens)
    );

  nodeForwarding = firstAttrsFromPaths {
    roots = [ runtimeTarget ];
    paths = [
      [ "forwarding" ]
      [ "forwardingIntent" ]
      [ "routing" ]
      [
        "semantic"
        "forwarding"
      ]
      [
        "semanticIntent"
        "forwarding"
      ]
    ];
  };

  nodeEgress = firstAttrsFromPaths {
    roots = [
      runtimeTarget
      nodeForwarding
    ];
    paths = [
      [ "egress" ]
      [
        "semantic"
        "egress"
      ]
      [
        "semanticIntent"
        "egress"
      ]
    ];
  };

  nodeForwardingEnabled = boolLikeFromPaths {
    roots = [
      runtimeTarget
      nodeForwarding
    ];
    paths = [
      [ "forwardingEnabled" ]
      [ "enabled" ]
      [ "authority" ]
      [ "routingAuthority" ]
      [ "forwardingAuthority" ]
      [ "forwardingResponsibility" ]
      [ "participatesInForwarding" ]
      [
        "forwarding"
        "enabled"
      ]
    ];
  };

  egressAuthority = boolLikeFromPaths {
    roots = [
      runtimeTarget
      nodeForwarding
      nodeEgress
    ];
    paths = [
      [ "egressAuthority" ]
      [ "exitAuthority" ]
      [ "upstreamSelectionAuthority" ]
      [ "authority" ]
      [
        "egress"
        "authority"
      ]
    ];
  };

  natEnabled = boolLikeFromPaths {
    roots = [
      runtimeTarget
      nodeForwarding
      nodeEgress
    ];
    paths = [
      [ "natEnabled" ]
      [ "nat" ]
      [
        "nat"
        "enable"
      ]
      [ "masquerade" ]
      [
        "masquerade"
        "enable"
      ]
      [
        "egress"
        "nat"
      ]
      [
        "egress"
        "nat"
        "enable"
      ]
      [
        "egress"
        "masquerade"
      ]
      [
        "egress"
        "masquerade"
        "enable"
      ]
    ];
  };

  explicitLocalAdapterNames = sortedStrings (
    resolveInterfaceTokens (stringListFromPaths {
      roots = [
        runtimeTarget
        nodeForwarding
      ];
      paths = [
        [ "localAdapterInterfaces" ]
        [ "localAdapters" ]
        [
          "forwarding"
          "localAdapterInterfaces"
        ]
        [
          "forwarding"
          "localAdapters"
        ]
        [
          "participation"
          "localAdapterInterfaces"
        ]
        [
          "participation"
          "localAdapters"
        ]
        [
          "interfaceRoles"
          "localAdapters"
        ]
      ];
    })
    ++ map (entry: entry.name) (
      lib.filter (entry: boolOrFalse entry.explicit.explicitLocalAdapter) interfaceEntries
    )
  );

  explicitUplinkNames = sortedStrings (
    resolveInterfaceTokens (stringListFromPaths {
      roots = [
        runtimeTarget
        nodeForwarding
        nodeEgress
      ];
      paths = [
        [ "uplinkInterfaces" ]
        [ "uplinks" ]
        [
          "forwarding"
          "uplinkInterfaces"
        ]
        [
          "forwarding"
          "uplinks"
        ]
        [
          "participation"
          "uplinkInterfaces"
        ]
        [
          "participation"
          "uplinks"
        ]
        [
          "egress"
          "exitInterfaces"
        ]
        [
          "egress"
          "upstreamSelectionInterfaces"
        ]
        [
          "egress"
          "uplinkInterfaces"
        ]
        [
          "interfaceRoles"
          "uplinks"
        ]
      ];
    })
    ++ map (entry: entry.name) (
      lib.filter (
        entry: boolOrFalse entry.explicit.explicitUplink || boolOrFalse entry.explicit.explicitExitEligible
      ) interfaceEntries
    )
  );

  explicitTransitNames = sortedStrings (
    resolveInterfaceTokens (stringListFromPaths {
      roots = [
        runtimeTarget
        nodeForwarding
      ];
      paths = [
        [ "transitInterfaces" ]
        [ "transits" ]
        [
          "forwarding"
          "transitInterfaces"
        ]
        [
          "forwarding"
          "transits"
        ]
        [
          "participation"
          "transitInterfaces"
        ]
        [
          "participation"
          "transits"
        ]
        [
          "interfaceRoles"
          "transits"
        ]
      ];
    })
    ++ map (entry: entry.name) (
      lib.filter (entry: boolOrFalse entry.explicit.explicitTransit) interfaceEntries
    )
  );

  explicitWanNames = sortedStrings (
    resolveInterfaceTokens (stringListFromPaths {
      roots = [
        runtimeTarget
        nodeForwarding
        nodeEgress
      ];
      paths = [
        [ "wanInterfaces" ]
        [ "wans" ]
        [
          "egress"
          "wanInterfaces"
        ]
      ];
    })
    ++ map (entry: entry.name) (
      lib.filter (entry: boolOrFalse entry.explicit.explicitWan) interfaceEntries
    )
  );

  explicitExitEligibleNames = sortedStrings (
    resolveInterfaceTokens (stringListFromPaths {
      roots = [
        runtimeTarget
        nodeForwarding
        nodeEgress
      ];
      paths = [
        [ "exitInterfaces" ]
        [ "upstreamSelectionInterfaces" ]
        [
          "egress"
          "exitInterfaces"
        ]
        [
          "egress"
          "upstreamSelectionInterfaces"
        ]
      ];
    })
    ++ map (entry: entry.name) (
      lib.filter (entry: boolOrFalse entry.explicit.explicitExitEligible) interfaceEntries
    )
  );

  explicitNatInterfaces = sortedStrings (
    resolveInterfaceTokens (stringListFromPaths {
      roots = [
        runtimeTarget
        nodeForwarding
        nodeEgress
      ];
      paths = [
        [ "natInterfaces" ]
        [ "masqueradeInterfaces" ]
        [
          "nat"
          "interfaces"
        ]
        [
          "masquerade"
          "interfaces"
        ]
        [
          "egress"
          "natInterfaces"
        ]
        [
          "egress"
          "nat"
          "interfaces"
        ]
        [
          "egress"
          "masqueradeInterfaces"
        ]
        [
          "egress"
          "masquerade"
          "interfaces"
        ]
      ];
    })
    ++ map (entry: entry.name) (
      lib.filter (entry: boolOrFalse entry.explicit.explicitNatEnabled) interfaceEntries
    )
  );

  explicitClampMssInterfaces = sortedStrings (
    resolveInterfaceTokens (stringListFromPaths {
      roots = [
        runtimeTarget
        nodeForwarding
        nodeEgress
      ];
      paths = [
        [ "clampMssInterfaces" ]
        [ "tcpMssClampInterfaces" ]
        [
          "clampMss"
          "interfaces"
        ]
        [
          "tcpMssClamp"
          "interfaces"
        ]
        [
          "egress"
          "clampMssInterfaces"
        ]
        [
          "egress"
          "tcpMssClampInterfaces"
        ]
        [
          "egress"
          "clampMss"
          "interfaces"
        ]
        [
          "egress"
          "tcpMssClamp"
          "interfaces"
        ]
      ];
    })
    ++ map (entry: entry.name) (
      lib.filter (entry: boolOrFalse entry.explicit.explicitClampMss) interfaceEntries
    )
  );

  fallbackWanNames = sortedStrings (
    wanIfs ++ map (entry: entry.name) (lib.filter (entry: entry.sourceKind == "wan") interfaceEntries)
  );

  fallbackP2pNames = sortedStrings (
    map (entry: entry.name) (lib.filter (entry: entry.sourceKind == "p2p") interfaceEntries)
  );

  fallbackLocalAdapterNames = sortedStrings (
    lanIfs
    ++ map (entry: entry.name) (
      lib.filter (entry: entry.sourceKind != "wan" && entry.sourceKind != "p2p") interfaceEntries
    )
  );

  fallbackLanNames = sortedStrings (
    lanIfs
    ++ map (entry: entry.name) (
      lib.filter (entry: !(builtins.elem entry.name fallbackWanNames)) interfaceEntries
    )
  );

  resolvedLocalAdapterNames =
    if explicitLocalAdapterNames != [ ] then explicitLocalAdapterNames else fallbackLocalAdapterNames;

  resolvedWanNames = if explicitWanNames != [ ] then explicitWanNames else fallbackWanNames;

  resolvedLanNames =
    if explicitLocalAdapterNames != [ ] then explicitLocalAdapterNames else fallbackLanNames;

  resolvedTransitNames =
    if explicitTransitNames != [ ] then explicitTransitNames else fallbackP2pNames;

  resolvedUplinkNames = if explicitUplinkNames != [ ] then explicitUplinkNames else fallbackWanNames;

  resolvedAccessUplinkNames =
    if explicitUplinkNames != [ ] then
      explicitUplinkNames
    else if fallbackP2pNames != [ ] then
      fallbackP2pNames
    else
      fallbackWanNames;

  normalizeForwardPair =
    pair:
    if !builtins.isAttrs pair then
      null
    else
      let
        inIfs = resolveInterfaceTokens (
          (attrOr pair "in" [ ]) ++ (attrOr pair "iifname" [ ]) ++ (attrOr pair "from" [ ])
        );

        outIfs = resolveInterfaceTokens (
          (attrOr pair "out" [ ]) ++ (attrOr pair "oifname" [ ]) ++ (attrOr pair "to" [ ])
        );

        action = if pair ? action && builtins.isString pair.action then pair.action else "accept";
      in
      if inIfs == [ ] || outIfs == [ ] then
        null
      else
        {
          "in" = inIfs;
          "out" = outIfs;
          inherit action;
        }
        // lib.optionalAttrs (pair ? comment && builtins.isString pair.comment && pair.comment != "") {
          comment = pair.comment;
        };

  normalizedExplicitForwardPairs = lib.filter (pair: pair != null) (
    map normalizeForwardPair (
      lib.concatMap asList (valuesFromPaths {
        roots = [
          runtimeTarget
          nodeForwarding
        ];
        paths = [
          [ "forwardPairs" ]
          [
            "firewall"
            "forwardPairs"
          ]
          [
            "policy"
            "forwardPairs"
          ]
          [
            "forwarding"
            "forwardPairs"
          ]
          [
            "forwarding"
            "firewall"
            "forwardPairs"
          ]
        ];
      })
    )
  );

  accessForwardPairs =
    if normalizedExplicitForwardPairs != [ ] then
      normalizedExplicitForwardPairs
    else
      lib.filter (pair: pair != null) [
        (
          if resolvedLocalAdapterNames != [ ] && resolvedAccessUplinkNames != [ ] then
            {
              "in" = resolvedLocalAdapterNames;
              "out" = resolvedAccessUplinkNames;
              action = "accept";
              comment = "access-local-to-uplink";
            }
          else
            null
        )
        (
          if resolvedLocalAdapterNames != [ ] && resolvedAccessUplinkNames != [ ] then
            {
              "in" = resolvedAccessUplinkNames;
              "out" = resolvedLocalAdapterNames;
              action = "accept";
              comment = "access-uplink-to-local";
            }
          else
            null
        )
      ];

  coreForwardPairs =
    if normalizedExplicitForwardPairs != [ ] then
      normalizedExplicitForwardPairs
    else
      lib.filter (pair: pair != null) [
        (
          if resolvedLanNames != [ ] && resolvedWanNames != [ ] then
            {
              "in" = resolvedLanNames;
              "out" = resolvedWanNames;
              action = "accept";
              comment = "core-lan-to-wan";
            }
          else
            null
        )
      ];

  upstreamSelectorForwardPairs =
    if normalizedExplicitForwardPairs != [ ] then
      normalizedExplicitForwardPairs
    else if builtins.length resolvedTransitNames < 2 then
      [ ]
    else
      lib.concatMap (
        inIf:
        map (outIf: {
          "in" = [ inIf ];
          "out" = [ outIf ];
          action = "accept";
          comment = "upstream-selector-${inIf}-to-${outIf}";
        }) (lib.filter (candidate: candidate != inIf) resolvedTransitNames)
      ) resolvedTransitNames;

  coreNatInterfaces =
    if natEnabled == false then
      [ ]
    else if explicitNatInterfaces != [ ] then
      explicitNatInterfaces
    else if natEnabled == true && explicitExitEligibleNames != [ ] then
      explicitExitEligibleNames
    else if natEnabled == true then
      resolvedWanNames
    else
      [ ];

  accessClampMssInterfaces =
    if explicitClampMssInterfaces != [ ] then
      explicitClampMssInterfaces
    else if resolvedTransitNames == [ ] then
      resolvedWanNames
    else
      [ ];

  coreClampMssInterfaces =
    if explicitClampMssInterfaces != [ ] then
      explicitClampMssInterfaces
    else if coreNatInterfaces != [ ] then
      coreNatInterfaces
    else
      [ ];

  authoritativeAccessForwarding =
    normalizedExplicitForwardPairs != [ ]
    || nodeForwardingEnabled == false
    || (explicitLocalAdapterNames != [ ] && explicitUplinkNames != [ ]);

  authoritativeCoreForwarding =
    normalizedExplicitForwardPairs != [ ]
    || nodeForwardingEnabled == false
    || (explicitLocalAdapterNames != [ ] && explicitUplinkNames != [ ]);

  authoritativeCoreNat =
    explicitNatInterfaces != [ ]
    || natEnabled == false
    || (natEnabled == true && explicitExitEligibleNames != [ ]);

  authoritativeUpstreamSelectorForwarding =
    normalizedExplicitForwardPairs != [ ]
    || nodeForwardingEnabled == false
    || explicitTransitNames != [ ];

  _uplinks = uplinks;
in
{
  inherit
    interfaceEntries
    interfaceNames
    nodeForwardingEnabled
    egressAuthority
    natEnabled
    explicitLocalAdapterNames
    explicitUplinkNames
    explicitTransitNames
    explicitWanNames
    explicitExitEligibleNames
    explicitNatInterfaces
    explicitClampMssInterfaces
    normalizedExplicitForwardPairs
    resolvedLocalAdapterNames
    resolvedUplinkNames
    resolvedAccessUplinkNames
    resolvedTransitNames
    resolvedWanNames
    resolvedLanNames
    accessForwardPairs
    coreForwardPairs
    upstreamSelectorForwardPairs
    coreNatInterfaces
    accessClampMssInterfaces
    coreClampMssInterfaces
    authoritativeAccessForwarding
    authoritativeCoreForwarding
    authoritativeCoreNat
    authoritativeUpstreamSelectorForwarding
    ;
}
