{
  lib,
  interfaces,
  interfaceNames,
  renderedInterfaceNames,
  networkManagerInterfaces,
  keepInterfaceRoutesInMain,
  isUpstreamSelectorCoreInterface,
  advertisedOnlinkRoutesByInterface,
  policyRoutingByInterface,
  mkRoute,
  isExternalValidationDelegatedPrefixRoute,
  delegatedPrefixSourceForRoute,
  mkDynamicWanNetworkConfig,
  needsIpv6AcceptRA,
  common,
}:

let
  inherit (common) interfaceNameFor;
  peers = import ./policy-routing/peers.nix {
    inherit lib common;
  };

  routeGateway =
    route:
    if builtins.isString (route.via4 or null) && route.via4 != "" then
      { family = 4; gateway = route.via4; }
    else if builtins.isString (route.via6 or null) && route.via6 != "" then
      { family = 6; gateway = route.via6; }
    else
      null;

  interfacePeerForFamily =
    family: iface:
    let
      address = peers.addressForFamily family iface;
    in
    if family == 6 then peers.ipv6PeerFor127 address else peers.ipv4PeerFor31 address;

  routeGatewayMatchesInterface =
    iface: route:
    let gateway = routeGateway route;
    in gateway == null || interfacePeerForFamily gateway.family iface == gateway.gateway;

  interfaceUnits = builtins.listToAttrs (
    lib.filter (entry: entry != null) (
      lib.imap0 (
        index: ifName:
        let
          iface = interfaces.${ifName};
          interfaceName = renderedInterfaceNames.${ifName};
          rawRoutes = (iface.routes or [ ]) ++ (advertisedOnlinkRoutesByInterface.${ifName} or [ ]);
          renderedInterfaceName = renderedInterfaceNames.${ifName};
          keepStaticRoutesInMain =
            keepInterfaceRoutesInMain || isUpstreamSelectorCoreInterface renderedInterfaceName;
          mainStaticRawRoutes =
            if keepInterfaceRoutesInMain then
              staticRawRoutes
            else
              lib.filter (route: routeGatewayMatchesInterface iface route) staticRawRoutes;
          staticRawRoutes = lib.filter (
            route: !(isExternalValidationDelegatedPrefixRoute route)
          ) rawRoutes;
          policyMainRoutes =
            lib.optionals keepInterfaceRoutesInMain (
              map (route: builtins.removeAttrs route [ "Table" ]) (policyRoutingByInterface.routes.${ifName} or [ ])
            );
        in
        if builtins.elem interfaceName networkManagerInterfaces then
          null
        else
          {
            name = "10-${interfaceName}";
            value = {
              matchConfig.Name = interfaceName;
              networkConfig = { ConfigureWithoutCarrier = true; } // mkDynamicWanNetworkConfig iface;
              address = iface.addresses or [ ];
              routes =
                (lib.optionals keepStaticRoutesInMain (
                  lib.filter (route: route != null) (map mkRoute mainStaticRawRoutes)
                ))
                ++ policyMainRoutes
                ++ (policyRoutingByInterface.routes.${ifName} or [ ]);
              routingPolicyRules = policyRoutingByInterface.rules.${ifName} or [ ];
            };
          }
      ) interfaceNames
    )
  );

  dynamicDelegatedRoutes = lib.concatLists (
    map (
      ifName:
      let
        iface = interfaces.${ifName};
        interfaceName = renderedInterfaceNames.${ifName};
      in
      lib.imap0 (
        index: route:
        let
          sourceFile = delegatedPrefixSourceForRoute route;
          gateway =
            if builtins.isString (route.via6 or null) && route.via6 != "" then
              route.via6
            else if builtins.isString (route.via4 or null) && route.via4 != "" then
              route.via4
            else
              null;
        in
        if sourceFile == null then
          null
        else
          {
            name = "delegated-prefix-route-${interfaceName}-${builtins.toString index}";
            inherit interfaceName sourceFile gateway;
            metric = route.metric or null;
          }
      ) (iface.routes or [ ])
    ) interfaceNames
  );
in
{
  inherit interfaceUnits;

  ipv6AcceptRAInterfaces = map interfaceNameFor (
    lib.filter (
      iface:
      let
        interfaceName = interfaceNameFor iface;
      in
      needsIpv6AcceptRA iface && !(builtins.elem interfaceName networkManagerInterfaces)
    ) (builtins.attrValues interfaces)
  );

  dynamicDelegatedRoutes = lib.filter (route: route != null) dynamicDelegatedRoutes;
}
