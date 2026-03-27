{
  lib,
  fabricNodeContext,
  containerName,
  ...
}:

let
  ifName = "${containerName}-fabric";

  ifaces =
    if fabricNodeContext ? interfaces && builtins.isAttrs fabricNodeContext.interfaces then
      fabricNodeContext.interfaces
    else if fabricNodeContext ? effectiveRuntimeRealization
      && builtins.isAttrs fabricNodeContext.effectiveRuntimeRealization
      && fabricNodeContext.effectiveRuntimeRealization ? interfaces
      && builtins.isAttrs fabricNodeContext.effectiveRuntimeRealization.interfaces
    then
      fabricNodeContext.effectiveRuntimeRealization.interfaces
    else
      throw ''
        container: fabricNodeContext missing `interfaces` attrset

        fabricNodeContext:
        ${builtins.toJSON fabricNodeContext}
      '';

  candidates =
    lib.filterAttrs (
      _: v:
      builtins.isAttrs v
      && (
        (v.kind or null) == "p2p"
        || (v.sourceKind or null) == "p2p"
      )
    ) ifaces;

  names = builtins.attrNames candidates;

  _one =
    if builtins.length names == 1 then
      true
    else
      throw ''
        container: expected exactly 1 p2p interface for core role

        found: ${toString (builtins.length names)}

        candidates:
        ${builtins.concatStringsSep "\n  - " ([ "" ] ++ names)}

        all interfaces:
        ${builtins.concatStringsSep "\n  - " ([ "" ] ++ builtins.attrNames ifaces)}
      '';

  ifaceName = builtins.head names;
  iface = candidates.${ifaceName};

  addr4 =
    if iface ? addr4 && iface.addr4 != null then
      iface.addr4
    else
      throw ''
        container: p2p iface '${ifaceName}' missing addr4

        iface:
        ${builtins.toJSON iface}
      '';

  addr6 =
    if iface ? addr6 && iface.addr6 != null then
      iface.addr6
    else
      throw ''
        container: p2p iface '${ifaceName}' missing addr6

        iface:
        ${builtins.toJSON iface}
      '';

  ifaceRoutes =
    if iface ? routes && builtins.isAttrs iface.routes then
      iface.routes
    else
      { };

  mkStaticRoutes =
    family:
    let
      routeKey = if family == 4 then "ipv4" else "ipv6";
      viaKey = if family == 4 then "via4" else "via6";
      rawRoutes =
        if builtins.hasAttr routeKey ifaceRoutes && builtins.isList ifaceRoutes.${routeKey} then
          ifaceRoutes.${routeKey}
        else
          [ ];
    in
    map (
      route:
      {
        Destination = route.dst;
        Gateway = route.${viaKey};
        GatewayOnLink = true;
      }
    ) (
      builtins.filter (
        route:
        builtins.isAttrs route
        && (route.proto or null) != "connected"
        && route ? dst
        && builtins.isString route.dst
        && builtins.hasAttr viaKey route
        && builtins.isString route.${viaKey}
      ) rawRoutes
    );

  staticRoutes = (mkStaticRoutes 4) ++ (mkStaticRoutes 6);
in
{
  systemd.network.networks."20-${ifName}" = {
    matchConfig.Name = ifName;

    addresses = [
      { Address = addr4; }
      { Address = addr6; }
    ];

    routes = staticRoutes;

    networkConfig = {
      IPv4Forwarding = true;
      IPv6Forwarding = true;
      ConfigureWithoutCarrier = true;
    };
  };
}
