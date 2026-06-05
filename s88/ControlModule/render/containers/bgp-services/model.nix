{ lib
, renderedModel
,
}:

let
  sortedAttrNames = attrs: lib.sort builtins.lessThan (builtins.attrNames attrs);

  uniqueBy =
    keyFn: values:
    builtins.attrValues (
      builtins.listToAttrs (
        map
          (value: {
            name = keyFn value;
            inherit value;
          })
          values
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

  runtimeTarget =
    if renderedModel ? runtimeTarget && builtins.isAttrs renderedModel.runtimeTarget then
      renderedModel.runtimeTarget
    else
      { };

  requireInt =
    path: value:
    if builtins.isInt value then
      value
    else
      throw "CPM renderer contract update required: ${path} must be an integer";

  requireNonEmptyString =
    path: value:
    if builtins.isString value && value != "" then
      value
    else
      throw "CPM renderer contract update required: ${path} must be a non-empty string";

  requireBool =
    path: value:
    if builtins.isBool value then
      value
    else
      throw "CPM renderer contract update required: ${path} must be an explicit boolean";

  routingModeRaw = runtimeTarget.routingMode or "static";
  routingMode = if builtins.isString routingModeRaw then lib.toLower routingModeRaw else "static";

  bgp =
    if routingMode != "bgp" then
      if runtimeTarget ? bgp && builtins.isAttrs runtimeTarget.bgp then runtimeTarget.bgp else { }
    else
      let
        raw =
          if runtimeTarget ? bgp && builtins.isAttrs runtimeTarget.bgp then
            runtimeTarget.bgp
          else
            throw "CPM renderer contract update required: runtimeTarget.bgp must be an attrset when runtimeTarget.routingMode = \"bgp\"";
        _asn = requireInt "runtimeTarget.bgp.asn" (raw.asn or null);
        _neighbors =
          if !builtins.hasAttr "neighbors" raw || builtins.isList raw.neighbors then
            true
          else
            throw "CPM renderer contract update required: runtimeTarget.bgp.neighbors must be a list";
      in
      builtins.seq _asn (builtins.seq _neighbors raw);

  neighborsRaw = if bgp ? neighbors && builtins.isList bgp.neighbors then bgp.neighbors else [ ];

  loopback = renderedModel.loopback or { };
  interfaces = renderedModel.interfaces or { };
  renderedNetworks = renderedModel.networks or { };
  runtimeTargetNetworks = runtimeTarget.networks or { };

  tenantNetworksForFamily =
    family:
    lib.unique (
      lib.filter builtins.isString (
        lib.concatMap
          (
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
              directNetworks =
                if family == 4 then
                  [
                    (if semantic ? network && builtins.isAttrs semantic.network then semantic.network.ipv4 or null else null)
                    (semantic.subnet4 or null)
                    (semantic.addr4 or null)
                  ]
                else
                  [
                    (if semantic ? network && builtins.isAttrs semantic.network then semantic.network.ipv6 or null else null)
                    (semantic.subnet6 or null)
                    (semantic.addr6 or null)
                  ];
              familyRoutes = if family == 4 then routeTree.ipv4 or [ ] else routeTree.ipv6 or [ ];
            in
            if sourceKind != "tenant" then [ ] else directNetworks ++ map (route: route.dst) (lib.filter isConnectedRoute familyRoutes)
          )
          (sortedAttrNames interfaces)
      )
    );

  tenantNetworksFromAttrs =
    family: attrs:
    lib.unique (
      lib.filter builtins.isString (
        map
          (
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
          )
          (sortedAttrNames attrs)
      )
    );

  validateNeighbor =
    idx: neighbor:
    if !builtins.isAttrs neighbor then
      throw "CPM renderer contract update required: runtimeTarget.bgp.neighbors[${builtins.toString idx}] must be a neighbor record"
    else
      let
        path = "runtimeTarget.bgp.neighbors[${builtins.toString idx}]";
        peer4 = stripCidr (neighbor.peer_addr4 or null);
        peer6 = stripCidr (neighbor.peer_addr6 or null);
        peerAddr4 = if builtins.isString peer4 && peer4 != "" then peer4 else null;
        peerAddr6 = if builtins.isString peer6 && peer6 != "" then peer6 else null;
        _peerAsn = requireInt "${path}.peer_asn" (neighbor.peer_asn or null);
        _peerAddr =
          if peerAddr4 != null || peerAddr6 != null then
            true
          else
            throw "CPM renderer contract update required: ${path} must carry peer_addr4 or peer_addr6";
        _updateSource =
          if neighbor ? update_source then
            builtins.seq (requireNonEmptyString "${path}.update_source" neighbor.update_source) true
          else
            true;
        _routeReflectorClient =
          if neighbor ? route_reflector_client then
            builtins.seq (requireBool "${path}.route_reflector_client" neighbor.route_reflector_client) true
          else
            true;
      in
      builtins.seq _peerAsn (builtins.seq _peerAddr (builtins.seq _updateSource (builtins.seq _routeReflectorClient {
        peerAsn = neighbor.peer_asn;
        inherit peerAddr4 peerAddr6;
        updateSource = if neighbor ? update_source then neighbor.update_source else null;
        routeReflectorClient = if neighbor ? route_reflector_client then neighbor.route_reflector_client else false;
      })));

  normalizedNeighbors =
    builtins.genList
      (idx: validateNeighbor idx (builtins.elemAt neighborsRaw idx))
      (builtins.length neighborsRaw);

  ipv4Neighbors = lib.sort (a: b: a.peerAddr4 < b.peerAddr4) (
    uniqueBy
      (
        neighbor:
        builtins.concatStringsSep "|" [
          neighbor.peerAddr4
          (toString neighbor.peerAsn)
          (if neighbor.updateSource != null then neighbor.updateSource else "")
          (if neighbor.routeReflectorClient then "rr" else "no-rr")
        ]
      )
      (lib.filter (neighbor: neighbor.peerAddr4 != null) normalizedNeighbors)
  );

  ipv6Neighbors = lib.sort (a: b: a.peerAddr6 < b.peerAddr6) (
    uniqueBy
      (
        neighbor:
        builtins.concatStringsSep "|" [
          neighbor.peerAddr6
          (toString neighbor.peerAsn)
          (if neighbor.updateSource != null then neighbor.updateSource else "")
          (if neighbor.routeReflectorClient then "rr" else "no-rr")
        ]
      )
      (lib.filter (neighbor: neighbor.peerAddr6 != null) normalizedNeighbors)
  );
in
{
  inherit
    bgp
    ipv4Neighbors
    ipv6Neighbors
    runtimeTarget
    stripCidr
    ;

  loopback = loopback;
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
}
