{
  lib,
  containerModel,
  interfaceKeyForRenderedName,
}:

let
  runtimeTarget =
    if containerModel ? runtimeTarget && builtins.isAttrs containerModel.runtimeTarget then
      containerModel.runtimeTarget
    else
      { };

  advertisements =
    if runtimeTarget ? advertisements && builtins.isAttrs runtimeTarget.advertisements then
      runtimeTarget.advertisements
    else
      { };

  ipv6RaAdvertisements =
    if advertisements ? ipv6Ra && builtins.isList advertisements.ipv6Ra then
      lib.filter (entry: builtins.isAttrs entry && (entry.enabled or true) != false) advertisements.ipv6Ra
    else
      [ ];

  interfaceKeyForAdvertisedInterface =
    name:
    if !(builtins.isString name) || name == "" then null else interfaceKeyForRenderedName name;
in
{
  advertisedOnlinkRoutesByInterface = builtins.foldl' (
    acc: adv:
    let
      rawInterface =
        if builtins.isString (adv.interface or null) && adv.interface != "" then
          adv.interface
        else if builtins.isString (adv.bindInterface or null) && adv.bindInterface != "" then
          adv.bindInterface
        else
          null;
      ifName = interfaceKeyForAdvertisedInterface rawInterface;
      prefixes =
        if adv ? prefixes && builtins.isList adv.prefixes then
          lib.filter builtins.isString adv.prefixes
        else
          [ ];
      routes = map (prefix: {
        dst = prefix;
        scope = "link";
      }) prefixes;
    in
    if ifName == null || routes == [ ] then
      acc
    else
      acc // { ${ifName} = (acc.${ifName} or [ ]) ++ routes; }
  ) { } ipv6RaAdvertisements;
}
