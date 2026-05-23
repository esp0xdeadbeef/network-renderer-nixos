{
  lib,
  interfaces,
  laneAccessForRenderedName,
  peers,
}:

let
  isHostPrefix =
    source:
    let
      prefix = source.prefix or "";
    in
    builtins.isString prefix
    && (
      ((source.family or 4) == 4 && lib.hasSuffix "/32" prefix)
      || ((source.family or 4) == 6 && lib.hasSuffix "/128" prefix)
    );

  matchesInterfaceOrigin =
    interfaceName: source:
    let
      accesses =
        if builtins.isAttrs (source.origin or null) && builtins.isList (source.origin.accesses or null) then
          source.origin.accesses
        else
          [ ];
      access = laneAccessForRenderedName interfaceName;
    in
    accesses == [ ] || (access != null && builtins.elem access accesses);
in
{
  routeFor =
    ifName: source:
    let
      iface = interfaces.${ifName};
      family = source.family or 4;
      gateway =
        if family == 6 then
          peers.ipv6PeerFor127 (peers.addressForFamily 6 iface)
        else
          peers.ipv4PeerFor31 (peers.addressForFamily 4 iface);
    in
    if gateway == null || !(isHostPrefix source) then
      null
    else
      {
        dst = source.prefix;
        intent.kind = "runtime-origin-source-reachability";
      }
      // (
        if family == 6 then
          { via6 = gateway; }
        else
          { via4 = gateway; }
      );

  inherit matchesInterfaceOrigin;
}
