{
  lib,
  common,
  interfaces,
  renderedInterfaceNames,
  isUpstreamSelector,
  isUpstreamSelectorCoreInterface,
  addressForFamily,
  ipv4PeerFor31,
  ipv6PeerFor127,
  returnDestinationsForTenant,
}:

let
  inherit (common) policyTenantKeyFor;
in
{
  forUpstreamCore =
    targetName: sourceIfName:
    let
      sourceIface = interfaces.${sourceIfName} or { };
      sourceRenderedName = renderedInterfaceNames.${sourceIfName};
      tenantKey = policyTenantKeyFor sourceRenderedName;
      peer4 = ipv4PeerFor31 (addressForFamily 4 sourceIface);
      peer6 = ipv6PeerFor127 (addressForFamily 6 sourceIface);
    in
    if !(isUpstreamSelector && isUpstreamSelectorCoreInterface targetName) || tenantKey == null then
      [ ]
    else
      lib.filter (route: route != null) (
        map (
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
        ) (returnDestinationsForTenant tenantKey)
      );
}
