{
  lib,
  containerModel,
  common,
}:

let
  delegatedPrefixSourceForRoute =
    route:
    if builtins.isString (route.sourceFile or null) && route.sourceFile != "" then
      route.sourceFile
    else if
      builtins.isAttrs (route.delegatedPrefix or null)
      && builtins.isString (route.delegatedPrefix.sourceFile or null)
    then
      route.delegatedPrefix.sourceFile
    else
      null;
in
{
  inherit delegatedPrefixSourceForRoute;

  isExternalValidationDelegatedPrefixRoute = route: delegatedPrefixSourceForRoute route != null;

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
          // lib.optionalAttrs (route ? table && builtins.isInt route.table) { Table = route.table; }
          // lib.optionalAttrs (route ? metric && builtins.isInt route.metric) { Metric = route.metric; }
          // lib.optionalAttrs ((route.policyOnly or false) == true) { _s88PolicyOnly = true; }
        else
          null
      else
        {
          Gateway = gateway;
          GatewayOnLink = true;
        }
        // lib.optionalAttrs (destination != null) { Destination = destination; }
        // lib.optionalAttrs (builtins.isString (route.preferredSource or null) && route.preferredSource != "") {
          PreferredSource = route.preferredSource;
        }
        // lib.optionalAttrs (route ? table && builtins.isInt route.table) { Table = route.table; }
        // lib.optionalAttrs (route ? metric && builtins.isInt route.metric) { Metric = route.metric; }
        // lib.optionalAttrs ((route.policyOnly or false) == true) { _s88PolicyOnly = true; }
        //
          lib.optionalAttrs
            (builtins.isAttrs (route.intent or null) && builtins.isString (route.intent.kind or null))
            {
              _s88IntentKind = route.intent.kind;
            }
        // lib.optionalAttrs (builtins.isString (route.sourceFile or null) && route.sourceFile != "") {
          inherit (route) sourceFile;
        }
        // lib.optionalAttrs (builtins.isAttrs (route.delegatedPrefix or null)) {
          inherit (route) delegatedPrefix;
        }
        // lib.optionalAttrs (route ? family) { inherit (route) family; };
}
