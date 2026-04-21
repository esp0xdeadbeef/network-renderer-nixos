{
  lib,
  renderedModel,
}:

let
  sortedAttrNames = attrs: lib.sort builtins.lessThan (builtins.attrNames attrs);

  runtimeTarget =
    if renderedModel ? runtimeTarget && builtins.isAttrs renderedModel.runtimeTarget then
      renderedModel.runtimeTarget
    else
      { };

  routingModeRaw = runtimeTarget.routingMode or "static";
  routingMode = if builtins.isString routingModeRaw then lib.toLower routingModeRaw else "static";

  bgp = if runtimeTarget ? bgp && builtins.isAttrs runtimeTarget.bgp then runtimeTarget.bgp else { };

  asn = bgp.asn or null;

  neighborsRaw = if bgp ? neighbors && builtins.isList bgp.neighbors then bgp.neighbors else [ ];

  loopback = renderedModel.loopback or { };
  interfaces = renderedModel.interfaces or { };
  renderedNetworks = renderedModel.networks or { };
  runtimeTargetNetworks = runtimeTarget.networks or { };

  uniqueBy =
    keyFn: values:
    builtins.attrValues (
      builtins.listToAttrs (
        map (value: {
          name = keyFn value;
          inherit value;
        }) values
      )
    );

  stripCidr =
    value:
    if !builtins.isString value then
      null
    else
      let
        match = builtins.match "([^/]+)/?.*" value;
      in
      if match == null then value else builtins.elemAt match 0;

  isIpv6 = value: builtins.isString value && lib.hasInfix ":" value;

  isConnectedRoute =
    route:
    builtins.isAttrs route
    && builtins.isString (route.proto or null)
    && route.proto == "connected"
    && builtins.isString (route.dst or null);

  tenantNetworksForFamily =
    family:
    lib.unique (
      lib.filter builtins.isString (
        lib.concatMap (
          ifName:
          let
            iface = interfaces.${ifName};
            sourceKind =
              if builtins.isString (iface.sourceKind or null) then
                iface.sourceKind
              else if
                iface ? semanticInterface
                && builtins.isAttrs iface.semanticInterface
                && builtins.isString (iface.semanticInterface.sourceKind or null)
              then
                iface.semanticInterface.sourceKind
              else
                null;
            semantic =
              if iface ? semanticInterface && builtins.isAttrs iface.semanticInterface then
                iface.semanticInterface
              else
                iface;
            routeTree =
              if semantic ? routes && builtins.isAttrs semantic.routes then
                semantic.routes
              else if iface ? routes && builtins.isAttrs iface.routes then
                iface.routes
              else
                { };
          in
          if sourceKind != "tenant" then
            [ ]
          else
            (
              if family == 4 then
                [
                  (
                    if semantic ? network && builtins.isAttrs semantic.network then
                      semantic.network.ipv4 or null
                    else
                      null
                  )
                  (semantic.subnet4 or null)
                  (semantic.addr4 or null)
                ]
              else
                [
                  (
                    if semantic ? network && builtins.isAttrs semantic.network then
                      semantic.network.ipv6 or null
                    else
                      null
                  )
                  (semantic.subnet6 or null)
                  (semantic.addr6 or null)
                ]
            )
            ++ (
              let
                familyRoutes = if family == 4 then routeTree.ipv4 or [ ] else routeTree.ipv6 or [ ];
              in
              map (route: route.dst) (lib.filter isConnectedRoute familyRoutes)
            )
        ) (sortedAttrNames interfaces)
      )
    );

  tenantNetworksFromAttrs =
    family: attrs:
    lib.unique (
      lib.filter builtins.isString (
        map (
          networkName:
          let
            network = attrs.${networkName};
          in
          if !builtins.isAttrs network then
            null
          else if family == 4 then
            network.ipv4 or null
          else
            network.ipv6 or null
        ) (sortedAttrNames attrs)
      )
    );

  networks4 = lib.unique (
    lib.filter builtins.isString (
      (lib.optional (!isIpv6 (loopback.addr4 or null)) (loopback.addr4 or null))
      ++ (tenantNetworksForFamily 4)
      ++ (tenantNetworksFromAttrs 4 renderedNetworks)
      ++ (tenantNetworksFromAttrs 4 runtimeTargetNetworks)
    )
  );

  networks6 = lib.unique (
    lib.filter builtins.isString (
      (lib.optional (isIpv6 (loopback.addr6 or null)) (loopback.addr6 or null))
      ++ (tenantNetworksForFamily 6)
      ++ (tenantNetworksFromAttrs 6 renderedNetworks)
      ++ (tenantNetworksFromAttrs 6 runtimeTargetNetworks)
    )
  );

  normalizedNeighbors = lib.filter (neighbor: neighbor != null) (
    map (
      neighbor:
      if !builtins.isAttrs neighbor || !builtins.isInt (neighbor.peer_asn or null) then
        null
      else
        let
          peer4 = stripCidr (neighbor.peer_addr4 or null);
          peer6 = stripCidr (neighbor.peer_addr6 or null);
        in
        {
          peerAsn = neighbor.peer_asn;
          peerAddr4 = if builtins.isString peer4 && peer4 != "" then peer4 else null;
          peerAddr6 = if builtins.isString peer6 && peer6 != "" then peer6 else null;
          updateSource =
            if builtins.isString (neighbor.update_source or null) && neighbor.update_source != "" then
              neighbor.update_source
            else
              null;
          routeReflectorClient = neighbor.route_reflector_client or false;
        }
    ) neighborsRaw
  );

  ipv4Neighbors = lib.sort (a: b: a.peerAddr4 < b.peerAddr4) (
    uniqueBy (
      neighbor:
      builtins.concatStringsSep "|" [
        neighbor.peerAddr4
        (toString neighbor.peerAsn)
        (if neighbor.updateSource != null then neighbor.updateSource else "")
        (if neighbor.routeReflectorClient then "rr" else "no-rr")
      ]
    ) (lib.filter (neighbor: neighbor.peerAddr4 != null) normalizedNeighbors)
  );

  ipv6Neighbors = lib.sort (a: b: a.peerAddr6 < b.peerAddr6) (
    uniqueBy (
      neighbor:
      builtins.concatStringsSep "|" [
        neighbor.peerAddr6
        (toString neighbor.peerAsn)
        (if neighbor.updateSource != null then neighbor.updateSource else "")
        (if neighbor.routeReflectorClient then "rr" else "no-rr")
      ]
    ) (lib.filter (neighbor: neighbor.peerAddr6 != null) normalizedNeighbors)
  );

  routerId =
    let
      candidates = lib.filter builtins.isString [
        (stripCidr (loopback.addr4 or null))
      ];
    in
    if candidates != [ ] then builtins.head candidates else "1.1.1.1";

  neighborPrelude =
    neighbors:
    lib.concatMap (
      neighbor:
      [
        "  neighbor ${neighbor.peer} remote-as ${toString neighbor.peerAsn}"
      ]
      ++ lib.optional (
        neighbor.updateSource != null
      ) "  neighbor ${neighbor.peer} update-source ${neighbor.updateSource}"
    ) neighbors;

  neighborFamilyLines =
    neighborKey: neighbors: family: networks:
    [
      "  address-family ${family} unicast"
    ]
    ++ map (network: "    network ${network}") networks
    ++ lib.concatMap (
      neighbor:
      [
        "    neighbor ${neighbor.${neighborKey}} activate"
      ]
      ++ lib.optional neighbor.routeReflectorClient "    neighbor ${neighbor.${neighborKey}} route-reflector-client"
    ) neighbors
    ++ [
      "  exit-address-family"
    ];

  frrConfig =
    lib.concatStringsSep "\n" (
      [
        "ip forwarding"
        "ipv6 forwarding"
        "!"
        "router bgp ${toString asn}"
        "  bgp router-id ${routerId}"
        "  no bgp ebgp-requires-policy"
        "  no bgp network import-check"
      ]
      ++ neighborPrelude (map (neighbor: neighbor // { peer = neighbor.peerAddr4; }) ipv4Neighbors)
      ++ neighborPrelude (map (neighbor: neighbor // { peer = neighbor.peerAddr6; }) ipv6Neighbors)
      ++ [
        "  !"
      ]
      ++ neighborFamilyLines "peerAddr4" ipv4Neighbors "ipv4" networks4
      ++ [
        "  !"
      ]
      ++ neighborFamilyLines "peerAddr6" ipv6Neighbors "ipv6" networks6
    )
    + "\n";

  enableBgp = routingMode == "bgp" && builtins.isInt asn;
in
lib.optionalAttrs enableBgp {
  services.frr = {
    bgpd.enable = true;
    config = frrConfig;
  };
}
