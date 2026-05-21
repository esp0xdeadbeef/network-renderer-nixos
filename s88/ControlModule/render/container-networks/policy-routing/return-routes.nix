{ lib
, common
, interfaces
, renderedInterfaceNames
, isUpstreamSelector
, isUpstreamSelectorCoreInterface
, addressForFamily
, ipv4PeerFor31
, ipv6PeerFor127
, returnDestinationsForTenant
,
}:

let
  inherit (common) policyTenantKeyFor;

  isDefaultDestination =
    dst:
    dst == "0.0.0.0/0"
    || dst == "::/0"
    || dst == "0000:0000:0000:0000:0000:0000:0000:0000/0";

  explicitDestinationsForTenant =
    tenantKey:
    lib.concatMap
      (
        ifName:
        let
          renderedName = renderedInterfaceNames.${ifName};
        in
        if policyTenantKeyFor renderedName != tenantKey then
          [ ]
        else
          lib.concatMap
            (
              route:
              let
                dst = route.dst or null;
              in
              if builtins.isString dst && !(isDefaultDestination dst) then [ dst ] else [ ]
            )
            (interfaces.${ifName}.routes or [ ])
      )
      (builtins.attrNames interfaces);
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
          ((returnDestinationsForTenant tenantKey) ++ (explicitDestinationsForTenant tenantKey))
      );
}
