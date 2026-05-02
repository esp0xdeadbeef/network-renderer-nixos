{
  lib,
  containerModel,
  common,
}:

let
  externalValidationDelegatedPrefixSources =
    if
      containerModel ? externalValidationDelegatedPrefixSources
      && builtins.isAttrs containerModel.externalValidationDelegatedPrefixSources
    then
      containerModel.externalValidationDelegatedPrefixSources
    else
      { };

  delegatedPrefixSourceForRoute =
    route:
    if
      builtins.isAttrs route
      && builtins.isString (route.dst or null)
      && builtins.hasAttr route.dst externalValidationDelegatedPrefixSources
    then
      externalValidationDelegatedPrefixSources.${route.dst}
    else
      null;
in
{
  inherit delegatedPrefixSourceForRoute;

  isExternalValidationDelegatedPrefixRoute =
    route: delegatedPrefixSourceForRoute route != null;

  mkRoute =
    route:
    if !builtins.isAttrs route then
      null
    else
      let
        destination = if route ? dst && route.dst != null then route.dst else null;
        destinationIsIpv6 = builtins.isString destination && lib.hasInfix ":" destination;
        gateway =
          if destinationIsIpv6 && route ? via6 && route.via6 != null then
            route.via6
          else if destinationIsIpv6 && route ? via4 && route.via4 != null then
            route.via4
          else if route ? via4 && route.via4 != null then
            route.via4
          else if route ? via6 && route.via6 != null then
            route.via6
          else
            null;
      in
      if gateway == null then
        if route ? scope && route.scope == "link" && builtins.isString destination && destination != "" then
          {
            Destination = destination;
            Scope = "link";
          }
        else
          null
      else
        {
          Gateway = gateway;
          GatewayOnLink = true;
        }
        // lib.optionalAttrs (destination != null) { Destination = destination; }
        // lib.optionalAttrs (route ? table && builtins.isInt route.table) { Table = route.table; }
        // lib.optionalAttrs (route ? metric && builtins.isInt route.metric) { Metric = route.metric; };
}
