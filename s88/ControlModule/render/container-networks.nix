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

  attrsOrEmpty = value: if builtins.isAttrs value then value else { };
  listOrEmpty = value: if builtins.isList value then value else [ ];

  baseInterfaces = containerModel.interfaces or { };
  runtimeInterfaces = attrsOrEmpty (
    (attrsOrEmpty ((attrsOrEmpty (containerModel.runtimeTarget or null)).effectiveRuntimeRealization or null)).interfaces or null
  );

  isProviderOwnedOverlayInterface =
    iface:
    let
      backingRef = attrsOrEmpty (iface.backingRef or null);
      connectivity = attrsOrEmpty (iface.connectivity or null);
      connectivityBackingRef = attrsOrEmpty (connectivity.backingRef or null);
      materialization = attrsOrEmpty ((attrsOrEmpty (iface.materialization or null)).nixos or null);
    in
    (
      (iface.sourceKind or null) == "overlay"
      || (connectivity.sourceKind or null) == "overlay"
      || (backingRef.kind or null) == "overlay"
      || (connectivityBackingRef.kind or null) == "overlay"
    )
    && (materialization.ownsInterface or false) != true
    && (materialization.owner or null) != "network-renderer-nixos";

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

  providerInterfaceFor =
    ifName: iface:
    let
      runtimeIfName =
        if builtins.isString (iface.runtimeIfName or null) && iface.runtimeIfName != "" then
          iface.runtimeIfName
        else if builtins.isString (iface.renderedIfName or null) && iface.renderedIfName != "" then
          iface.renderedIfName
        else
          ifName;
      backingRef = attrsOrEmpty (iface.backingRef or null);
    in
    iface
    // {
      ifName = ifName;
      sourceKind = iface.sourceKind or "overlay";
      renderedIfName = runtimeIfName;
      containerInterfaceName = runtimeIfName;
      addresses = addressListForInterface iface;
      routes = routeListForInterface iface;
      backingRef = backingRef;
      connectivity = (attrsOrEmpty (iface.connectivity or null)) // {
        sourceKind = iface.sourceKind or "overlay";
        backingRef = backingRef;
      };
      providerCreated = true;
      materialization = (attrsOrEmpty (iface.materialization or null)) // {
        nixos = (attrsOrEmpty ((attrsOrEmpty (iface.materialization or null)).nixos or null)) // {
          ownsInterface = false;
        };
      };
    };

  providerInterfaces =
    builtins.mapAttrs providerInterfaceFor (
      lib.filterAttrs (ifName: iface: !(builtins.hasAttr ifName baseInterfaces) && isProviderOwnedOverlayInterface iface) runtimeInterfaces
    );

  interfaces = baseInterfaces // providerInterfaces;
  interfaceView = import ./container-networks/interface-view.nix {
    inherit lib interfaces common;
  };

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
      ;
    inherit (routeRender) mkRoute;
    inherit (routeRender) isExternalValidationDelegatedPrefixRoute;
  };

  loopback = import ./container-networks/loopback.nix {
    inherit lib containerModel;
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
    inherit (routeRender)
      mkRoute
      isExternalValidationDelegatedPrefixRoute
      delegatedPrefixSourceForRoute
      ;
    inherit (dynamicWan) mkDynamicWanNetworkConfig needsIpv6AcceptRA;
    inherit (advertisements) advertisedOnlinkRoutesByInterface;
    inherit (policyRouting) policyRoutingByInterface;
    inherit (classes) keepInterfaceRoutesInMain isUpstreamSelectorCoreInterface;
  };

  dynamicSourceForwardRules =
    lib.concatMap
      (
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
                action = pair.action or "accept";
                family = pair.family or 6;
                comment = pair.comment or "runtime-routed-prefix-public-egress";
              }) (pair."out" or [ ])
            ) (pair."in" or [ ])
          ) pair.sourceFiles
      )
      (if forwardingIntent == null then [ ] else forwardingIntent.normalizedExplicitForwardPairs or [ ]);
in
{
  networks = loopback.loopbackUnit // hostBridgeWan.networks // interfaceUnits.interfaceUnits;
  ipv6AcceptRAInterfaces = lib.unique (
    hostBridgeWan.ipv6AcceptRAInterfaces ++ interfaceUnits.ipv6AcceptRAInterfaces
  );
  inherit (interfaceUnits) dynamicDelegatedRoutes;
  inherit (interfaceUnits) staticProviderRoutes;
  inherit dynamicSourceForwardRules;
  dynamicPolicySourceRules = policyRouting.policyRoutingByInterface.dynamicSourceRules or [ ];
}
