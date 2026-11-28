{
  lib,
  containerModel,

  canonicalRoutes ? [ ],
  canonicalForwarding ? { },

  canonicalSites ? { },
  uplinks,
  wanUplinkName,
  forwardingIntent ? null,
  firewallRuleset ? null,
}:

let
  common = import ./container-networks/common.nix { inherit lib; };
  providerOverlayRuntimeInterfaces = import ./provider-overlay-runtime-interfaces.nix {
    inherit lib;
  };

  attrsOrEmpty = value: if builtins.isAttrs value then value else { };
  listOrEmpty = value: if builtins.isList value then value else [ ];

  firewallTableName =
    let
      ruleset = if builtins.isString firewallRuleset then firewallRuleset else "";
      afterTable = builtins.elemAt (lib.splitString "table inet " ruleset) 1;
      name = builtins.elemAt (lib.splitString " " afterTable) 0;
    in
    if name == "" then "router" else name;

  baseInterfaces = containerModel.interfaces or { };
  pppoeService = attrsOrEmpty ((attrsOrEmpty (containerModel.services or null)).pppoe or null);
  pppoeOwnedInterfaceNames = lib.unique (
    lib.filter (name: builtins.isString name && name != "") [
      ((attrsOrEmpty (pppoeService.client or null)).interface or null)
      ((attrsOrEmpty (pppoeService.server or null)).interface or null)
    ]
  );
  pppoeMarkedInterfaces = lib.mapAttrs (
    name: iface:
    if builtins.elem name pppoeOwnedInterfaceNames then iface // { _s88PppoeOwned = true; } else iface
  ) baseInterfaces;
  runtimeInterfaces = attrsOrEmpty (
    (attrsOrEmpty (
      (attrsOrEmpty (containerModel.runtimeTarget or null)).effectiveRuntimeRealization or null
    )).interfaces or null
  );

  addressListForInterface =
    iface:
    lib.unique (
      listOrEmpty (iface.addresses or null)
      ++ lib.optional (builtins.isString (iface.addr4 or null) && iface.addr4 != "") iface.addr4
      ++ lib.optional (builtins.isString (iface.addr6 or null) && iface.addr6 != "") iface.addr6
    );

  routeListForInterface =
    iface:
    let
      routes = iface.routes or [ ];
    in
    if builtins.isList routes then
      routes
    else if builtins.isAttrs routes then
      listOrEmpty (routes.ipv4 or null) ++ listOrEmpty (routes.ipv6 or null)
    else
      [ ];

  providerOverlayRoutes = import ./container-networks/provider-overlay-routes.nix;

  providerInterfaces = providerOverlayRuntimeInterfaces.materializeMissingProviderOverlayInterfaces {
    inherit runtimeInterfaces;
    renderedInterfaces = baseInterfaces;
    decorate =
      { iface, ... }:
      {
        addresses = addressListForInterface iface;
        routes = providerOverlayRoutes.normalize (routeListForInterface iface);
        materialization = (attrsOrEmpty (iface.materialization or null)) // {
          nixos = (attrsOrEmpty ((attrsOrEmpty (iface.materialization or null)).nixos or null)) // {
            ownsInterface = false;
          };
        };
      };
  };

  interfaces = pppoeMarkedInterfaces // providerInterfaces;
  interfaceView = import ./container-networks/interface-view.nix {
    inherit lib interfaces common;
  };
  renderedInterfaceNames = interfaceView.renderedInterfaceNames;

  runtimeInterfaceToContainerName = lib.listToAttrs (
    lib.filter
      (entry: entry.name != null && entry.name != "" && entry.value != null && entry.value != "")
      (
        map (
          name:
          let
            iface = interfaces.${name} or { };
          in
          {
            name = iface.renderedIfName or null;
            value = iface.containerInterfaceName or (iface.interfaceName or null);
          }
        ) (builtins.attrNames interfaces)
      )
  );

  networkManagerInterfaces =
    if
      containerModel ? networkManagerWanInterfaces
      && builtins.isList containerModel.networkManagerWanInterfaces
    then
      lib.filter builtins.isString containerModel.networkManagerWanInterfaces
    else
      [ ];

  routeRender = import ./container-networks/routes.nix {
    inherit lib containerModel common;
  };

  dynamicWan = import ./container-networks/dynamic-wan.nix {
    inherit
      lib
      uplinks
      wanUplinkName
      common
      ;
  };

  hostBridgeWan = import ./container-networks/host-bridge-wan.nix {
    inherit
      lib
      containerModel
      uplinks
      wanUplinkName
      ;
  };

  advertisements = import ./container-networks/advertisements.nix {
    inherit lib containerModel;
    inherit (interfaceView) interfaceKeyForRenderedName;
  };

  classes = import ./container-networks/classes.nix {
    inherit lib common containerModel;
    inherit interfaces;
    inherit (interfaceView) interfaceNames renderedInterfaceNames;
  };

  canonicalRoutingAuthoritative =
    let
      mine =
        if selfRuntimeTarget == null then
          [ ]
        else
          builtins.filter (r: (r.target or null) == selfRuntimeTarget) canonicalRoutes;
    in
    mine != [ ];

  policyRouting = import ./container-networks/policy-routing.nix {
    inherit canonicalRoutingAuthoritative;
    inherit
      lib
      containerModel
      common
      forwardingIntent
      firewallRuleset
      ;
    inherit (interfaceView)
      interfaces
      interfaceNames
      renderedInterfaceNames
      laneAccessForRenderedName
      sourceKindForRenderedName
      upstreamLanesMatch
      ;
    inherit (classes)
      isSelector
      isUpstreamSelector
      isPolicy
      isDownstreamSelectorAccessInterface
      isDownstreamSelectorPolicyInterface
      isUpstreamSelectorCoreInterface
      isUpstreamSelectorPolicyInterface
      isPolicyDownstreamInterface
      isPolicyUpstreamInterface
      isOverlayInterface
      isCoreTransitInterface
      isAccessHostInterface
      ;
    inherit (routeRender) mkRoute;
    inherit (routeRender) isExternalValidationDelegatedPrefixRoute;
    inherit runtimeInterfaceToContainerName;
  };

  fs370Validation = import ./container-networks/policy-routing/fs370-validation.nix {
    inherit lib common;
  };

  fs370MaterializationValidation = fs370Validation.validateContainer {
    inherit
      containerModel
      interfaces
      renderedInterfaceNames
      forwardingIntent
      firewallRuleset
      ;
    nodeName = containerModel.unitName or containerModel.containerName or "unknown";
    policyRoutingByInterface = policyRouting.policyRoutingByInterface;
    isExpectedPolicyInterface = classes.isDownstreamSelectorPolicyInterface;
    isExpectedAccessInterface = classes.isDownstreamSelectorAccessInterface;
  };

  loopback = import ./container-networks/loopback.nix {
    inherit lib containerModel;
  };

  pppoeVlanBridge = import ./container-networks/pppoe-vlan-bridge.nix {
    inherit
      lib
      interfaces
      uplinks
      wanUplinkName
      ;
    inherit (interfaceView) interfaceNames renderedInterfaceNames;
  };

  interfaceUnits = import ./container-networks/interface-units.nix {
    inherit
      lib
      containerModel
      interfaces
      networkManagerInterfaces
      common
      ;
    inherit (interfaceView) interfaceNames renderedInterfaceNames;
    inherit canonicalPolicyRoutesByInterface modelledTenantPrefixes;
    inherit canonicalTenantLaneTableByInterface;
    inherit relationEgressInterfaces;
    skipInterfaceNames = builtins.attrNames (pppoeVlanBridge.bridgeInterfaces or { });
    inherit (routeRender)
      mkRoute
      isExternalValidationDelegatedPrefixRoute
      delegatedPrefixSourceForRoute
      ;
    inherit (dynamicWan)
      isDynamicallyAddressed
      mkDynamicWanNetworkConfig
      mkDynamicWanDhcpV4Config
      mkDynamicWanIpv6AcceptRAConfig
      needsIpv6AcceptRA
      ;
    inherit (advertisements) advertisedOnlinkRoutesByInterface;
    inherit (policyRouting) policyRoutingByInterface modeledScopedDestinationsByLane;
    inherit (classes) keepInterfaceRoutesInMain isUpstreamSelectorCoreInterface isAccessGateway;
  };

  dynamicSourceForwardRules =
    let
      pairs =
        if forwardingIntent == null then [ ] else forwardingIntent.normalizedExplicitForwardPairs or [ ];
      fromSourceFiles = lib.concatMap (
        pair:
        if !(builtins.isAttrs pair) || !(builtins.isList (pair.sourceFiles or null)) then
          [ ]
        else
          lib.concatMap (
            sourceFile:
            lib.concatMap (
              inIf:
              map (outIf: {
                inherit sourceFile inIf outIf;
                action =
                  pair.action
                    or (throw "FS-310-HDS-030-SDS-010-SMS-111: pair.action required by CPM provider contract, cannot default to 'accept'");
                family =
                  pair.family
                    or (throw "FS-310-HDS-030-SDS-010-SMS-111: pair.family required by CPM provider contract, cannot default to 6");
                comment = pair.comment or "runtime-routed-prefix-public-egress";
              }) (pair."out" or [ ])
            ) (pair."in" or [ ])
          ) pair.sourceFiles
      ) pairs;
      fromSourceRuntimePrefixes = lib.concatMap (
        pair:
        if !(builtins.isAttrs pair) || !(builtins.isList (pair.sourceRuntimePrefixes or null)) then
          [ ]
        else
          lib.concatMap (
            runtimePrefix:
            lib.concatMap (
              inIf:
              map (outIf: {
                sourceFile = runtimePrefix.sourceFile or null;
                inherit inIf outIf;
                action =
                  pair.action
                    or (throw "FS-310-HDS-030-SDS-010-SMS-111: pair.action required by CPM provider contract, cannot default to 'accept'");
                family = runtimePrefix.family or 6;
                comment = pair.comment or "runtime-routed-prefix-public-egress";
                deriveTenantPrefix = true;
                delegatedPrefixLength = runtimePrefix.delegatedPrefixLength or null;
                perTenantPrefixLength = runtimePrefix.perTenantPrefixLength or null;
                slot = runtimePrefix.slot or null;
              }) (pair."out" or [ ])
            ) (pair."in" or [ ])
          ) pair.sourceRuntimePrefixes
      ) pairs;
    in
    fromSourceFiles ++ fromSourceRuntimePrefixes;

  dynamicDestinationForwardRules = import ./container-networks/runtime-destination-forwarding.nix {
    inherit lib;
    pairs =
      if forwardingIntent == null then [ ] else forwardingIntent.normalizedExplicitForwardPairs or [ ];
  };

  selfRuntimeTarget =
    let
      rt = containerModel.runtimeTarget or null;
    in
    if builtins.isAttrs rt && builtins.isString (rt.target or null) then rt.target else null;

  canonicalRouteProjection =
    let
      mine =
        if selfRuntimeTarget == null then
          [ ]
        else
          builtins.filter (r: (r.target or null) == selfRuntimeTarget) canonicalRoutes;

      modelledNameFor =
        r:
        let
          rendered = r.runtimeIfName or null;
          renderedHits =
            if builtins.isString rendered && rendered != "" then
              builtins.filter (n: (renderedInterfaceNames.${n} or null) == rendered) interfaceView.interfaceNames
            else
              [ ];
          own = r.interface or null;
        in
        if renderedHits != [ ] then
          builtins.head renderedHits
        else if builtins.isString own && own != "" then
          own
        else
          null;
      factsOf = r: if builtins.isAttrs (r.facts or null) then r.facts else { };
      toRoute =
        r:
        let

          gateway =
            if builtins.isString (r.gateway or null) && r.gateway != "" then
              r.gateway
            else if builtins.isString (r.via4 or null) && r.via4 != "" then
              r.via4
            else if builtins.isString (r.via6 or null) && r.via6 != "" then
              r.via6
            else
              null;
        in
        {
          Destination = r.dst;
          Table = r.tableId;
        }
        // lib.optionalAttrs (gateway != null) {
          Gateway = gateway;
          GatewayOnLink = builtins.isString (r.preferredSource or null) && r.preferredSource != "";
        }
        // lib.optionalAttrs (gateway == null && !(builtins.isString r.dst && lib.hasInfix ":" r.dst)) {

          Scope = "link";
        }
        // lib.optionalAttrs (builtins.isInt (r.metric or null)) { Metric = r.metric; }
        // lib.optionalAttrs (builtins.isString (r.preferredSource or null) && r.preferredSource != "") {
          PreferredSource = r.preferredSource;
        }
        // lib.optionalAttrs (builtins.isString ((factsOf r).scope or null) && (factsOf r).scope != "") {
          Scope = (factsOf r).scope;
        };
      keyed = builtins.concatMap (
        r:
        let
          renderedName = modelledNameFor r;
        in
        if renderedName == null then
          [ ]
        else
          [
            {
              _ifName = renderedName;
              route = toRoute r;
            }
          ]
      ) (builtins.filter (r: builtins.isInt (r.tableId or null)) mine);

      advertisedDefaults = builtins.filter (
        r:
        (r.dst or null) == "0.0.0.0/0"
        && ((r.facts or { }).advertisedToClients or false)
        && builtins.isInt (r.tableId or null)
      ) mine;

      tenantIfNames = builtins.filter (n: builtins.isString n && n != "") (
        lib.unique (map modelledNameFor (builtins.filter (r: (r.sourceKind or null) == "tenant") mine))
      );

      laneDefaults = builtins.filter (
        r:
        (r.dst or null) == "0.0.0.0/0"
        && builtins.isInt (r.tableId or null)
        && builtins.isString ((r.facts or { }).lane.access or null)
      ) mine;

      laneOwnedDefaults = builtins.filter (
        r: ((r.facts or { }).lane.kind or null) == "access-uplink"
      ) laneDefaults;

      laneTableFor =
        lane:
        let
          candidatesFor =
            pool:
            builtins.filter (
              x:
              ((x.facts or { }).lane.access or null) == (lane.access or null)
              && (
                !(builtins.isString (lane.uplink or null)) || ((x.facts or { }).lane.uplink or null) == lane.uplink
              )
            ) pool;
          owned = candidatesFor laneOwnedDefaults;
          any_ = candidatesFor laneDefaults;
          ownedTables = lib.unique (map (x: x.tableId) owned);
        in
        if builtins.length ownedTables == 1 then
          builtins.head ownedTables
        else if any_ == [ ] then
          null
        else
          (builtins.head any_).tableId;
      laneLaneTableByInterface =
        let
          entries = builtins.filter (e: e.value != null) (
            map (
              ifName:
              let
                laneRef = (interfaces.${ifName}.backingRef or { }).lane or { };
                laneAccess = laneRef.access or null;
                laneUplink =
                  if builtins.isString (laneRef.uplink or null) then
                    laneRef.uplink
                  else if builtins.isList (laneRef.uplinks or null) && builtins.length laneRef.uplinks == 1 then
                    builtins.head laneRef.uplinks
                  else
                    null;
              in
              {
                name = ifName;
                value =
                  if builtins.isString laneAccess && laneAccess != "" then
                    laneTableFor {
                      access = laneAccess;
                      uplink = laneUplink;
                    }
                  else
                    null;
              }
            ) (builtins.attrNames interfaces)
          );
        in
        builtins.listToAttrs entries;
    in
    {
      byInterface = lib.mapAttrs (_: es: builtins.map (e: e.route) es) (lib.groupBy (e: e._ifName) keyed);

      tenantLaneTableByInterface =
        if advertisedDefaults == [ ] || tenantIfNames == [ ] then
          { }
        else
          lib.genAttrs tenantIfNames (_: (builtins.head advertisedDefaults).tableId);

      relationIngressTableByInterface =
        let
          rels = builtins.filter (r: (r.target or null) == selfRuntimeTarget) (
            canonicalForwarding.relations or [ ]
          );

          nameToIfName = builtins.listToAttrs (
            builtins.concatMap (
              ifName:
              let
                rendered = renderedInterfaceNames.${ifName} or null;
              in
              [
                {
                  name = ifName;
                  value = ifName;
                }
              ]
              ++ lib.optional (builtins.isString rendered && rendered != "") {
                name = rendered;
                value = ifName;
              }
            ) (builtins.attrNames interfaces)
          );

          tableForEgressRuntime =
            runtimeInterface:
            let
              egressIfName =
                if builtins.isString runtimeInterface && runtimeInterface != "" then
                  nameToIfName.${runtimeInterface} or null
                else
                  null;
              hits = builtins.filter (
                x:
                (egressIfName == null || modelledNameFor x == egressIfName)
                && (x.dst or null) == "0.0.0.0/0"
                && builtins.isInt (x.tableId or null)
              ) mine;
            in
            if hits == [ ] || egressIfName == null then null else (builtins.head hits).tableId;

          entries = builtins.filter (e: builtins.isString e.name && e.name != "" && e.value != null) (
            map (rel: {
              name =
                if builtins.isString (rel.fromInterface or null) && (rel.fromInterface or null) != "" then
                  nameToIfName.${rel.fromInterface} or null
                else
                  null;
              value = tableForEgressRuntime (rel.egressRuntimeInterface or null);
            }) rels
          );
        in
        builtins.listToAttrs entries;

      singleExitTableByInterface =
        let
          allDefaults = builtins.filter (
            r: (r.dst or null) == "0.0.0.0/0" && builtins.isInt (r.tableId or null)
          ) mine;
        in
        if builtins.length allDefaults != 1 then
          { }
        else
          let
            only = builtins.head allDefaults;
            egressIfName = modelledNameFor only;
          in
          lib.genAttrs (builtins.filter (n: n != egressIfName) (builtins.attrNames interfaces)) (
            _: only.tableId
          );

      inherit laneLaneTableByInterface;
    };

  canonicalPolicyRoutesByInterface = canonicalRouteProjection.byInterface;
  inherit (canonicalRouteProjection) tenantLaneTableByInterface;

  canonicalTenantLaneTableByInterface =
    canonicalRouteProjection.singleExitTableByInterface
    // canonicalRouteProjection.relationIngressTableByInterface
    // canonicalRouteProjection.laneLaneTableByInterface
    // canonicalRouteProjection.tenantLaneTableByInterface;

  relationEgressInterfaces =
    let
      logicalName = containerModel.unitName or containerModel.containerName or null;
      relations = canonicalForwarding.relations or [ ];

      selfTarget =
        let
          rt = containerModel.runtimeTarget or null;
        in
        if builtins.isAttrs rt && builtins.isString (rt.target or null) then rt.target else null;
      mine =
        if selfTarget == null then [ ] else builtins.filter (r: (r.target or null) == selfTarget) relations;
    in
    builtins.filter (x: x != null) (map (r: r.egressRuntimeInterface or null) mine);

  modelledTenantPrefixes =
    let
      sites = canonicalSites.sites or [ ];
      collect =
        value:
        if builtins.isAttrs value then
          builtins.concatLists (map (n: collect value.${n}) (builtins.attrNames value))
        else if builtins.isList value then
          builtins.concatLists (map collect value)
        else if builtins.isString value && lib.hasInfix "/" value then

          [ value ]
        else
          [ ];
    in
    lib.unique (builtins.concatMap (s: collect (s.facts.domains or { })) sites);

  allNetworks =
    loopback.loopbackUnit
    // hostBridgeWan.networks
    // (pppoeVlanBridge.networks or { })
    // interfaceUnits.interfaceUnits;

  interfaceUnitsWithUniquePolicyRoutes =
    let

      canonicalOwnerName =
        dst: table:
        lib.findFirst (name: name != null) null (
          map (
            modelKey:
            let
              routes = canonicalPolicyRoutesByInterface.${modelKey} or [ ];
              matches = builtins.any (
                route: (route.Destination or null) == dst && (route.Table or null) == table
              ) routes;
            in
            if matches then renderedInterfaceNames.${modelKey} or null else null
          ) (builtins.attrNames interfaces)
        );

      routeKey =
        route:
        "${toString (route.Table or 0)}|${route.Destination or ""}|${toString (route.Metric or 0)}"
        + "|${toString (route._s88PolicyOnly or false)}"
        + "|${toString (route._s88IntentKind or "-")}"

        + "|${toString (route.Gateway or "-")}"
        + "|${toString (route.PreferredSource or "-")}";

      isTable =
        value: builtins.isInt value || (builtins.isString value && builtins.match "[0-9]+" value != null);
      claimed = route: isTable (route.Table or null);
      step =
        acc: name:
        let
          unit = allNetworks.${name};

          routes = unit.routes or [ ];
          ownUnique =
            builtins.foldl'
              (
                state: route:
                if builtins.elem (routeKey route) state.seen then
                  state
                else
                  {
                    seen = state.seen ++ [ (routeKey route) ];
                    routes = state.routes ++ [ route ];
                  }
              )
              {
                seen = [ ];
                routes = [ ];
              }
              routes;

          keep = ownUnique.routes;
        in
        {
          seen = acc.seen ++ map routeKey (builtins.filter claimed keep);
          units = acc.units // {
            ${name} = unit // {
              routes = keep;
            };
          };
        };
    in
    (builtins.foldl' step {
      seen = [ ];
      units = { };
    } (lib.sort (a: b: a < b) (builtins.attrNames allNetworks))).units;

  output = {
    netdevs = pppoeVlanBridge.netdevs or { };
    networks = interfaceUnitsWithUniquePolicyRoutes;
    coreLaneInterfaces =
      if classes.isUpstreamSelector then
        lib.filter (
          name: classes.isUpstreamSelectorUplinkLane (renderedInterfaceNames.${name})
        ) interfaceView.interfaceNames
      else
        [ ];
    inherit renderedInterfaceNames;
    hasMultipathRoute = lib.any (
      network: lib.any (route: (route.MultiPathRoute or null) != null) (network.routes or [ ])
    ) (builtins.attrValues interfaceUnits.interfaceUnits);
    ecmpMembers =
      let
        allRoutes = lib.concatLists (
          lib.mapAttrsToList (_: routes: listOrEmpty routes) (policyRouting.rawRoutesByInterface or { })
        );
        multipathRoutes = lib.filter (
          route:
          builtins.isAttrs (route._s88Multipath or null) && ((route._s88Multipath.authority or null) != null)
        ) allRoutes;
        p2pPeers = import ./container-networks/policy-routing/peers.nix { inherit lib common; };
        interfaceAndLocalForGateway =
          gateway:
          let
            family = if lib.hasInfix ":" gateway then 6 else 4;
            matches = lib.filter (
              name:
              (
                if family == 6 then
                  p2pPeers.ipv6PeerFor127 (p2pPeers.addressForFamily 6 (interfaces.${name} or { }))
                else
                  p2pPeers.ipv4PeerFor31 (p2pPeers.addressForFamily 4 (interfaces.${name} or { }))
              ) == gateway
            ) interfaceView.interfaceNames;
          in
          if matches == [ ] then
            throw "FS-481-HDS-010-SDS-010-SMS-045: multipath ECMP gateway ${gateway} does not resolve to a modeled p2p interface; declare the peer interface in the CPM forwarding model instead of assuming one"
          else
            let
              name = builtins.head matches;
            in
            {
              interface = renderedInterfaceNames.${name};
              localAddress = p2pPeers.addressForFamily family (interfaces.${name} or { });
            };
      in
      lib.unique (
        map (
          route:
          let
            gateway =
              if route ? Gateway && builtins.isString route.Gateway then
                route.Gateway
              else
                throw "FS-481-HDS-010-SDS-010-SMS-045: multipath ECMP member is missing a gateway";
            table =
              if route ? _s88Table && builtins.isInt route._s88Table then
                route._s88Table
              else
                throw "FS-481-HDS-010-SDS-010-SMS-045: multipath ECMP member is missing its policy routing table";
            destination =
              if route ? Destination && builtins.isString route.Destination then
                route.Destination
              else
                throw "FS-481-HDS-010-SDS-010-SMS-045: multipath ECMP member is missing its destination prefix";
            loc = interfaceAndLocalForGateway gateway;
          in
          {
            inherit destination gateway table;
            interface = loc.interface;
            localAddress = loc.localAddress;
          }
        ) multipathRoutes
      );
    fabricBfdPeers =
      let
        p2pPeers = import ./container-networks/policy-routing/peers.nix { inherit lib common; };
        fabricIfNames = lib.filter (
          name: classes.isUpstreamSelectorCoreInterface (renderedInterfaceNames.${name})
        ) interfaceView.interfaceNames;
        peersForFamily =
          family: name:
          let
            localAddress = p2pPeers.addressForFamily family (interfaces.${name} or { });
            peer =
              if family == 6 then p2pPeers.ipv6PeerFor127 localAddress else p2pPeers.ipv4PeerFor31 localAddress;
          in
          if peer == null || localAddress == null then
            null
          else
            {
              inherit peer;
              interface = renderedInterfaceNames.${name};
              inherit localAddress;
            };
      in
      lib.unique (
        lib.filter (entry: entry != null) (
          lib.concatMap (name: [
            (peersForFamily 4 name)
            (peersForFamily 6 name)
          ]) fabricIfNames
        )
      );
    ipv6AcceptRAInterfaces = lib.unique (
      hostBridgeWan.ipv6AcceptRAInterfaces ++ interfaceUnits.ipv6AcceptRAInterfaces
    );
    inherit (interfaceUnits) dynamicDelegatedRoutes;
    inherit (interfaceUnits) staticProviderRoutes;
    inherit (interfaceUnits) staticProviderPolicyRules;
    inherit dynamicSourceForwardRules;
    inherit dynamicDestinationForwardRules;
    inherit firewallTableName;
    dynamicPolicySourceRules = policyRouting.policyRoutingByInterface.dynamicSourceRules or [ ];
  };
in
builtins.seq fs370MaterializationValidation output
