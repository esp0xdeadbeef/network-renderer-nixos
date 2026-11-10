{
  lib,
  containerModel,
  common,
}:

let
  ipNormalize = import ./ip-normalize.nix { inherit lib; };

  routeIdentity =
    route:
    builtins.toJSON (
      map (name: route.${name} or null) [
        "Destination"
        "Gateway"
        "GatewayOnLink"
        "Scope"
        "Table"
        "Metric"
        "PreferredSource"
        "family"
      ]
    );

  normalizeRoute =
    route:
    if !builtins.isAttrs route then
      route
    else
      route
      // lib.optionalAttrs (builtins.isString (route.Destination or null)) {
        Destination = ipNormalize.canonicalAddress route.Destination;
      }
      // lib.optionalAttrs (builtins.isString (route.Gateway or null)) {
        Gateway = ipNormalize.canonicalAddress route.Gateway;
      }
      // lib.optionalAttrs (builtins.isString (route.PreferredSource or null)) {
        PreferredSource = ipNormalize.canonicalAddress route.PreferredSource;
      };

  normalizeRoutes = map normalizeRoute;

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
  inherit normalizeRoute normalizeRoutes;

  dedupeRoutes =
    routes:
    let
      step =
        acc: route:
        let
          identity = routeIdentity route;
        in
        if builtins.isAttrs route && !(acc.seen ? "${identity}") then
          {
            seen = acc.seen // {
              "${identity}" = true;
            };
            kept = acc.kept ++ [ route ];
          }
        else
          acc;
      result = builtins.foldl' step {
        seen = { };
        kept = [ ];
      } routes;
    in
    result.kept;

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
          // lib.optionalAttrs (!(route ? metric && builtins.isInt route.metric)) { Metric = 50; }
          // lib.optionalAttrs ((route.policyOnly or false) == true) { _s88PolicyOnly = true; }
        else
          null
      else
        {
          Gateway = gateway;
          GatewayOnLink = true;
        }
        // lib.optionalAttrs (destination != null) { Destination = destination; }
        //
          lib.optionalAttrs (builtins.isString (route.preferredSource or null) && route.preferredSource != "")
            {
              PreferredSource = route.preferredSource;
            }
        // lib.optionalAttrs (route ? table && builtins.isInt route.table) { Table = route.table; }
        // lib.optionalAttrs (route ? metric && builtins.isInt route.metric) { Metric = route.metric; }
        // lib.optionalAttrs (!(route ? metric && builtins.isInt route.metric)) { Metric = 50; }
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
