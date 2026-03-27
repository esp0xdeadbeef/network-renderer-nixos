{ lib }:

{
  load =
    host:
    if host ? transitBridges && builtins.isAttrs host.transitBridges then
      host.transitBridges
    else
      { };

  names = transitBridges: builtins.attrNames transitBridges;

  namesForUplink =
    transitBridges: uplinkName:
    lib.filter (
      transitName:
      let
        transit = transitBridges.${transitName};
      in
      (transit.parentUplink or null) == uplinkName
    ) (builtins.attrNames transitBridges);
}
