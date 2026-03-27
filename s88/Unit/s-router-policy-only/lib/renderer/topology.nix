{
  lib,
  hostname,
}:

let
  asList =
    value:
    if value == null then
      [ ]
    else if builtins.isList value then
      value
    else
      [ value ];

  shortenIfName =
    name:
    if lib.stringLength name <= 15 then
      name
    else
      "if${builtins.substring 0 13 (builtins.hashString "sha256" name)}";

  mkRoute =
    route:
    if !(builtins.isAttrs route) || !(route ? dst) then
      abort ''
        renderer/lib/renderer/topology.nix
        hostname: ${hostname}
        runtimeIfName: n/a
        linkName: n/a
        error: invalid route in runtime interface
        route: ${builtins.toJSON route}
      ''
    else
      {
        Destination = route.dst;
      }
      // lib.optionalAttrs (route ? via4) { Gateway = route.via4; }
      // lib.optionalAttrs (route ? via6) { Gateway = route.via6; };
in
runtimeIfName: runtimeIf:
let
  sourceRenderedIfName =
    if runtimeIf ? renderedIfName && runtimeIf.renderedIfName != "" then
      runtimeIf.renderedIfName
    else
      abort ''
        renderer/lib/renderer/topology.nix
        hostname: ${hostname}
        runtimeIfName: ${runtimeIfName}
        linkName: n/a
        error: renderedIfName missing
      '';

  backingRef = runtimeIf.backingRef or { };

  linkName =
    if (backingRef.kind or null) == "link" && (backingRef.name or "") != "" then
      backingRef.name
    else
      null;

  addresses =
    (map (addr: { Address = addr; }) (asList (runtimeIf.addr4 or null)))
    ++ (map (addr: { Address = addr; }) (asList (runtimeIf.addr6 or null)));

  routes =
    map mkRoute (
      (runtimeIf.routes.ipv4 or [ ])
      ++ (runtimeIf.routes.ipv6 or [ ])
    );
in
{
  inherit runtimeIfName linkName addresses routes;

  renderedIfName = shortenIfName sourceRenderedIfName;
  sourceRenderedIfName = sourceRenderedIfName;

  runtimeIf = runtimeIf;
}
