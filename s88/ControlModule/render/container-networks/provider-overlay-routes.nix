let
  routeHasGateway =
    route:
    builtins.isString (route.via4 or null) && route.via4 != ""
    || builtins.isString (route.via6 or null) && route.via6 != ""
    || builtins.isString (route.Gateway or null) && route.Gateway != "";
in
{
  normalize =
    routes:
    map
      (
        route:
        if
          builtins.isAttrs route
          && builtins.isString (route.dst or null)
          && route.dst != ""
          && !(routeHasGateway route)
          && !(builtins.isString (route.scope or null) && route.scope != "")
        then
          route // { scope = "link"; }
        else
          route
      )
      routes;
}
