{
  lib,
  vlanId,
  transitVlanId ? vlanId,
  fabricNodeContext,
  tenantNetwork ? null,
  ...
}:

let
  splitCIDR =
    cidr:
    let
      parts = lib.splitString "/" cidr;
    in
    if builtins.length parts == 2 then
      {
        address = builtins.elemAt parts 0;
        prefix = builtins.elemAt parts 1;
      }
    else
      throw ''
        networkd-from-topology:

        Invalid CIDR '${cidr}'.
      '';

  firstIPv4InSubnet =
    cidr:
    let
      parsed = splitCIDR cidr;
      octets = lib.splitString "." parsed.address;
    in
    if builtins.length octets == 4 then
      "${builtins.elemAt octets 0}.${builtins.elemAt octets 1}.${builtins.elemAt octets 2}.1/${parsed.prefix}"
    else
      throw ''
        networkd-from-topology:

        Cannot derive router IPv4 from subnet '${cidr}'.
      '';

  firstIPv6InSubnet =
    cidr:
    let
      parsed = splitCIDR cidr;
      base = parsed.address;
      addr =
        if lib.hasSuffix "::" base then
          "${base}1"
        else
          "${base}::1";
    in
    "${addr}/${parsed.prefix}";

  tenantNetworkResolved =
    if tenantNetwork != null
      && builtins.isAttrs tenantNetwork
      && tenantNetwork ? ipv4
      && builtins.isString tenantNetwork.ipv4
      && tenantNetwork ? ipv6
      && builtins.isString tenantNetwork.ipv6
    then
      tenantNetwork
    else
      let
        interfaces =
          if fabricNodeContext ? effectiveRuntimeRealization
            && builtins.isAttrs fabricNodeContext.effectiveRuntimeRealization
            && fabricNodeContext.effectiveRuntimeRealization ? interfaces
            && builtins.isAttrs fabricNodeContext.effectiveRuntimeRealization.interfaces
          then
            fabricNodeContext.effectiveRuntimeRealization.interfaces
          else if fabricNodeContext ? interfaces && builtins.isAttrs fabricNodeContext.interfaces then
            fabricNodeContext.interfaces
          else
            { };

        tenantIfNames =
          builtins.filter (
            ifName:
            let
              iface = interfaces.${ifName};
            in
            builtins.isAttrs iface
            && (iface.sourceKind or null) == "tenant"
            && iface ? addr4
            && builtins.isString iface.addr4
            && iface ? addr6
            && builtins.isString iface.addr6
          ) (builtins.attrNames interfaces);

        tenantIface =
          if builtins.length tenantIfNames == 1 then
            interfaces.${builtins.head tenantIfNames}
          else
            throw ''
              networkd-from-topology:

              Expected exactly 1 tenant interface.

              Found:
              ${builtins.concatStringsSep "\n  - " ([ "" ] ++ tenantIfNames)}
            '';
      in
      {
        ipv4 = tenantIface.addr4;
        ipv6 = tenantIface.addr6;
      };

  interfaces =
    if fabricNodeContext ? effectiveRuntimeRealization
      && builtins.isAttrs fabricNodeContext.effectiveRuntimeRealization
      && fabricNodeContext.effectiveRuntimeRealization ? interfaces
      && builtins.isAttrs fabricNodeContext.effectiveRuntimeRealization.interfaces
    then
      fabricNodeContext.effectiveRuntimeRealization.interfaces
    else if fabricNodeContext ? interfaces && builtins.isAttrs fabricNodeContext.interfaces then
      fabricNodeContext.interfaces
    else
      throw ''
        networkd-from-topology:

        fabricNodeContext missing interfaces.

        fabricNodeContext:
        ${builtins.toJSON fabricNodeContext}
      '';

  interfaceNames = builtins.attrNames interfaces;

  transitIfName =
    let
      matches =
        builtins.filter (
          ifName:
          let
            iface = interfaces.${ifName};
          in
          builtins.isAttrs iface
          && (
            (iface.sourceKind or null) == "p2p"
            || (iface.kind or null) == "p2p"
          )
        ) interfaceNames;
    in
    if builtins.length matches == 1 then
      builtins.head matches
    else
      throw ''
        networkd-from-topology:

        Expected exactly 1 p2p transit interface.

        Found:
        ${builtins.concatStringsSep "\n  - " ([ "" ] ++ matches)}
      '';

  transitIf = interfaces.${transitIfName};

  tenantIfName =
    let
      matches =
        builtins.filter (
          ifName:
          let
            iface = interfaces.${ifName};
          in
          builtins.isAttrs iface
          && (iface.sourceKind or null) == "tenant"
        ) interfaceNames;
    in
    if builtins.length matches == 1 then
      builtins.head matches
    else
      null;

  tenantIf =
    if tenantIfName != null then
      interfaces.${tenantIfName}
    else
      { };

  lanAddr4 =
    if tenantIf ? addr4 && builtins.isString tenantIf.addr4 then
      firstIPv4InSubnet tenantIf.addr4
    else
      firstIPv4InSubnet tenantNetworkResolved.ipv4;

  lanAddr6 =
    if tenantIf ? addr6 && builtins.isString tenantIf.addr6 then
      firstIPv6InSubnet tenantIf.addr6
    else
      firstIPv6InSubnet tenantNetworkResolved.ipv6;

  trAddr4 =
    if transitIf ? addr4 && builtins.isString transitIf.addr4 then
      transitIf.addr4
    else
      throw ''
        networkd-from-topology:

        Transit interface '${transitIfName}' missing addr4.

        iface:
        ${builtins.toJSON transitIf}
      '';

  trAddr6 =
    if transitIf ? addr6 && builtins.isString transitIf.addr6 then
      transitIf.addr6
    else
      throw ''
        networkd-from-topology:

        Transit interface '${transitIfName}' missing addr6.

        iface:
        ${builtins.toJSON transitIf}
      '';

  mkStaticRoutes =
    family:
    let
      routes =
        if transitIf ? routes
          && builtins.isAttrs transitIf.routes
          && builtins.hasAttr family transitIf.routes
          && builtins.isList transitIf.routes.${family}
        then
          transitIf.routes.${family}
        else
          [ ];

      viaKey = if family == "ipv4" then "via4" else "via6";
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
      ) routes
    );

  transitRoutes = (mkStaticRoutes "ipv4") ++ (mkStaticRoutes "ipv6");
in
{
  networking.useNetworkd = true;
  systemd.network.enable = true;

  systemd.network.networks = {
    "10-lan" = {
      matchConfig.Name = "lan-${toString vlanId}";

      networkConfig = {
        DHCP = "no";
        IPv4Forwarding = true;
        IPv6Forwarding = true;
        IPv6AcceptRA = true;
        ConfigureWithoutCarrier = true;
      };

      linkConfig.RequiredForOnline = false;

      addresses = [
        { Address = lanAddr4; }
        { Address = lanAddr6; }
      ];
    };

    "20-transit" = {
      matchConfig.Name = "tr-${toString transitVlanId}";

      networkConfig = {
        DHCP = "no";
        IPv4Forwarding = true;
        IPv6Forwarding = true;
        IPv6AcceptRA = false;
        ConfigureWithoutCarrier = true;
      };

      linkConfig.RequiredForOnline = false;

      addresses = [
        { Address = trAddr4; }
        { Address = trAddr6; }
      ];

      routes = transitRoutes;
    };
  };
}
