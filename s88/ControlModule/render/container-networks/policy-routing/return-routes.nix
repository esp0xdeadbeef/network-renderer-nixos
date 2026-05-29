{ lib
, common
, interfaces
, renderedInterfaceNames
, isUpstreamSelector
, isUpstreamSelectorCoreInterface
, addressForFamily
, ipv4PeerFor31
, ipv6PeerFor127
, returnDestinationsForAccessUnit
, returnDestinationsForTenant
,
}:

let
  inherit (common) downstreamPairKeyFor policyTenantKeyFor;

  tenantKeyForInterface =
    name:
    let
      policyKey = policyTenantKeyFor name;
    in
    if policyKey != null then policyKey else downstreamPairKeyFor name;

  interfaceKeyForRenderedName =
    renderedName:
    lib.findFirst (name: renderedInterfaceNames.${name} == renderedName) null (builtins.attrNames interfaces);

  accessUnitForInterface =
    renderedName:
    let
      key = interfaceKeyForRenderedName renderedName;
      lane = if key == null then { } else (interfaces.${key}.backingRef or { }).lane or { };
    in
    if builtins.isAttrs lane && builtins.isString (lane.access or null) && lane.access != "" then
      lane.access
    else
      null;

  destinationsForInterface =
    renderedName:
    let
      accessUnit = accessUnitForInterface renderedName;
      ownerDestinations =
        if accessUnit == null then
          [ ]
        else
          returnDestinationsForAccessUnit accessUnit;
      tenantKey = tenantKeyForInterface renderedName;
      tenantDestinations =
        if tenantKey == null then
          [ ]
        else
          returnDestinationsForTenant tenantKey;
    in
    lib.unique (ownerDestinations ++ tenantDestinations);

  routesForDestinationsViaInterface =
    destinations: sourceIfName:
    let
      sourceIface = interfaces.${sourceIfName} or { };
      peer4 = ipv4PeerFor31 (addressForFamily 4 sourceIface);
      peer6 = ipv6PeerFor127 (addressForFamily 6 sourceIface);
    in
    if destinations == [ ] then
      [ ]
    else
      lib.filter (route: route != null) (
        map
          (
            dst:
            let
              isIpv6 = builtins.isString dst && lib.hasInfix ":" dst;
              gateway = if isIpv6 then peer6 else peer4;
            in
            if gateway == null then
              null
            else if isIpv6 then
              {
                inherit dst;
                via6 = gateway;
              }
            else
              {
                inherit dst;
                via4 = gateway;
              }
          )
          destinations
      );

  routesForTenantInterface =
    sourceIfName:
    let
      sourceRenderedName = renderedInterfaceNames.${sourceIfName};
    in
    routesForDestinationsViaInterface (destinationsForInterface sourceRenderedName) sourceIfName;
in
{
  forTenantInterface = routesForTenantInterface;

  forTenantOfInterfaceViaInterface =
    tenantInterfaceName: sourceIfName:
    routesForDestinationsViaInterface (destinationsForInterface tenantInterfaceName) sourceIfName;

  forUpstreamCore =
    targetName: sourceIfName:
    if !(isUpstreamSelector && isUpstreamSelectorCoreInterface targetName) then
      [ ]
    else
      routesForTenantInterface sourceIfName;
}
