{
  lib,
  interfaces,
  interfaceNames,
  renderedInterfaceNames,
  networkManagerInterfaces,
  keepInterfaceRoutesInMain,
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

  interfaceUnits = builtins.listToAttrs (
    lib.filter (entry: entry != null) (
      lib.imap0 (
        index: ifName:
        let
          iface = interfaces.${ifName};
          interfaceName = renderedInterfaceNames.${ifName};
          rawRoutes = (iface.routes or [ ]) ++ (advertisedOnlinkRoutesByInterface.${ifName} or [ ]);
          staticRawRoutes = lib.filter (
            route: !(isExternalValidationDelegatedPrefixRoute route)
          ) rawRoutes;
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
                (lib.optionals keepInterfaceRoutesInMain (
                  lib.filter (route: route != null) (map mkRoute staticRawRoutes)
                ))
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
