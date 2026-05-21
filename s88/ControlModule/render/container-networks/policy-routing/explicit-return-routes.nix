{ lib
, common
, interfaces
, interfaceNames
, renderedInterfaceNames
, addressForFamily
, ipv4PeerFor31
, ipv6PeerFor127
,
}:

let
  isDefaultRoute =
    route:
    (route.dst or null) == "0.0.0.0/0"
    || (route.dst or null) == "::/0"
    || (route.dst or null) == "0000:0000:0000:0000:0000:0000:0000:0000/0";

  explicitDestinationsForPolicyTenant =
    tenantKey:
    lib.concatMap
      (
        name:
        let
          renderedName = renderedInterfaceNames.${name};
        in
        if common.policyTenantKeyFor renderedName != tenantKey then
          [ ]
        else
          lib.concatMap
            (
              route:
              if builtins.isAttrs route && builtins.isString (route.dst or null) && !(isDefaultRoute route) then
                [ route.dst ]
              else
                [ ]
            )
            (interfaces.${name}.routes or [ ])
      )
      interfaceNames;
in
{
  forPolicyInterface =
    sourceIfName:
    let
      sourceIface = interfaces.${sourceIfName} or { };
      sourceRenderedName = renderedInterfaceNames.${sourceIfName};
      tenantKey = common.policyTenantKeyFor sourceRenderedName;
      peer4 = ipv4PeerFor31 (addressForFamily 4 sourceIface);
      peer6 = ipv6PeerFor127 (addressForFamily 6 sourceIface);
    in
    if tenantKey == null then
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
          (explicitDestinationsForPolicyTenant tenantKey)
      );
}
