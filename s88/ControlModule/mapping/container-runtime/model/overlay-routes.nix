{ lib, lookup }:

let
  addresses = import ./addresses.nix { inherit lib; };

  overlaySiteNameForInterface =
    iface:
    let
      backingId = if iface ? backingRef && builtins.isAttrs iface.backingRef then iface.backingRef.id or null else null;
      parts = if builtins.isString backingId then lib.splitString "::" backingId else [ ];
    in
    if builtins.length parts >= 3 then builtins.elemAt parts 1 else null;

  overlayNameForInterface =
    iface:
    if iface ? backingRef && builtins.isAttrs iface.backingRef && builtins.isString (iface.backingRef.name or null) then
      iface.backingRef.name
    else
      null;

  overlayRouteLike =
    route:
    builtins.isAttrs route
    && (
      (builtins.isString (route.proto or null) && route.proto == "overlay")
      || (route ? intent && builtins.isAttrs route.intent && (route.intent.kind or null) == "overlay-reachability")
    );

  enrichOverlayRoutesForInterface =
    { overlayEndpoints, iface }:
    let
      ifaceOverlayName = overlayNameForInterface iface;
      routes = if iface ? routes && builtins.isList iface.routes then iface.routes else [ ];
      resolveNextHopForRoute =
        route:
        let
          peerSite = if route ? peerSite && builtins.isString route.peerSite then route.peerSite else null;
          overlayName = if route ? overlay && builtins.isString route.overlay then route.overlay else ifaceOverlayName;
          endpointKey = if peerSite != null && overlayName != null then "${peerSite}::${overlayName}" else null;
          nextHop = if endpointKey != null then overlayEndpoints.${endpointKey} or { } else { };
        in
        {
          via4 = if nextHop ? via4 then nextHop.via4 else null;
          via6 = if nextHop ? via6 then nextHop.via6 else null;
        };
      peerLinkRoutes = lib.unique (
        lib.concatMap (
          route:
          if !overlayRouteLike route then
            [ ]
          else
            let nextHop = resolveNextHopForRoute route;
            in
            (lib.optional (nextHop.via4 != null) { dst = "${nextHop.via4}/32"; scope = "link"; })
            ++ (lib.optional (nextHop.via6 != null) { dst = "${nextHop.via6}/128"; scope = "link"; })
        ) routes
      );
    in
    peerLinkRoutes
    ++ map (
      route:
      if !overlayRouteLike route || (route ? via4 && route.via4 != null) || (route ? via6 && route.via6 != null) then
        route
      else
        let nextHop = resolveNextHopForRoute route;
        in
        route
        // lib.optionalAttrs (!(route ? via4) && nextHop.via4 != null) { via4 = nextHop.via4; }
        // lib.optionalAttrs (!(route ? via6) && nextHop.via6 != null) { via6 = nextHop.via6; }
    ) routes;

  enrichOverlayRoutesForContainer =
    { overlayEndpoints, containerRuntime }:
    let
      interfaces = builtins.mapAttrs (
        _: iface:
        if (iface.sourceKind or null) == "overlay" then
          iface // { routes = enrichOverlayRoutesForInterface { inherit overlayEndpoints iface; }; }
        else
          iface
      ) (containerRuntime.interfaces or { });
    in
    containerRuntime // { interfaces = interfaces; renderedInterfaces = interfaces; };

  overlayEndpointsForContainers =
    containers:
    builtins.foldl' (
      acc: containerRuntime:
      builtins.foldl' (
        inner: ifName:
        let
          iface = containerRuntime.interfaces.${ifName};
          siteName = overlaySiteNameForInterface iface;
          overlayName = overlayNameForInterface iface;
          key = if siteName != null && overlayName != null then "${siteName}::${overlayName}" else null;
          via4 = addresses.firstAddressMatching {
            addresses = iface.addresses or [ ];
            predicate = value: !(lib.hasInfix ":" value);
          };
          via6 = addresses.firstAddressMatching {
            addresses = iface.addresses or [ ];
            predicate = value: lib.hasInfix ":" value;
          };
        in
        if (iface.sourceKind or null) != "overlay" || key == null then
          inner
        else
          inner // { ${key} = { inherit via4 via6; }; }
      ) acc (lookup.sortedAttrNames (containerRuntime.interfaces or { }))
    ) { } (builtins.attrValues containers);
in
{
  enrichOverlayRoutesForContainers =
    containers:
    let overlayEndpoints = overlayEndpointsForContainers containers;
    in
    builtins.mapAttrs (
      _: containerRuntime:
      enrichOverlayRoutesForContainer { inherit overlayEndpoints containerRuntime; }
    ) containers;
}
