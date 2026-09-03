{
  lib,
  containerModel,
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

  policyRouting = import ./container-networks/policy-routing.nix {
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
    skipInterfaceNames = builtins.attrNames (pppoeVlanBridge.bridgeInterfaces or { });
    inherit (routeRender)
      mkRoute
      isExternalValidationDelegatedPrefixRoute
      delegatedPrefixSourceForRoute
      ;
    inherit (dynamicWan)
      mkDynamicWanNetworkConfig
      mkDynamicWanDhcpV4Config
      mkDynamicWanIpv6AcceptRAConfig
      needsIpv6AcceptRA
      ;
    inherit (advertisements) advertisedOnlinkRoutesByInterface;
    inherit (policyRouting) policyRoutingByInterface;
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
  output = {
    netdevs = pppoeVlanBridge.netdevs or { };
    networks =
      loopback.loopbackUnit
      // hostBridgeWan.networks
      // (pppoeVlanBridge.networks or { })
      // interfaceUnits.interfaceUnits;
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
        allRoutes = lib.concatLists (lib.mapAttrsToList (_: iface: (iface.routes or [ ])) interfaces);
        multipathRoutes = lib.filter (
          route: (route.multipath or null) != null && (route.multipath.authority or null) != null
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
              route.via4 or route.via6 or throw
                "FS-481-HDS-010-SDS-010-SMS-045: multipath ECMP member is missing a gateway (via4/via6)";
            table =
              route.Table or throw
                "FS-481-HDS-010-SDS-010-SMS-045: multipath ECMP member is missing its policy routing table";
            destination =
              route.dst or throw
                "FS-481-HDS-010-SDS-010-SMS-045: multipath ECMP member is missing its destination prefix";
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
      in
      lib.unique (
        lib.filter (peer: peer != null) (
          map (
            name:
            let
              peer = p2pPeers.ipv4PeerFor31 (p2pPeers.addressForFamily 4 (interfaces.${name} or { }));
            in
            if peer == null then
              null
            else
              {
                peer = peer;
                interface = renderedInterfaceNames.${name};
                localAddress = p2pPeers.addressForFamily 4 (interfaces.${name} or { });
              }
          ) fabricIfNames
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
