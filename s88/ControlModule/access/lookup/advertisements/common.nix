{ lib }:

{
  sortedAttrNames = attrs: lib.sort builtins.lessThan (builtins.attrNames attrs);

  asStringList =
    value:
    if value == null then
      [ ]
    else if builtins.isString value then
      [ value ]
    else if builtins.isList value then
      lib.filter builtins.isString value
    else
      [ ];

  mergeAttrs =
    values:
    builtins.foldl' (acc: value: if builtins.isAttrs value then acc // value else acc) { } values;

  firstOrNull = values: if values == [ ] then null else builtins.head values;

  ipv4AddressFromCIDR =
    cidr:
    let
      parts = if builtins.isString cidr then lib.splitString "/" cidr else [ ];
    in
    if builtins.length parts == 2 then builtins.elemAt parts 0 else null;

  defaultIPv4Pool =
    ipv4Address:
    if !builtins.isString ipv4Address then
      null
    else
      let
        octets = lib.splitString "." ipv4Address;
      in
      if builtins.length octets == 4 then
        "${builtins.elemAt octets 0}.${builtins.elemAt octets 1}.${builtins.elemAt octets 2}.100 - ${builtins.elemAt octets 0}.${builtins.elemAt octets 1}.${builtins.elemAt octets 2}.200"
      else
        null;

  boolField =
    attrs: names: fallback:
    let
      values = lib.filter builtins.isBool (
        map (
          name: if builtins.isAttrs attrs && builtins.hasAttr name attrs then attrs.${name} else null
        ) names
      );
    in
    if values == [ ] then fallback else builtins.head values;

  stringField =
    attrs: names: fallback:
    let
      values = lib.filter builtins.isString (
        map (
          name: if builtins.isAttrs attrs && builtins.hasAttr name attrs then attrs.${name} else null
        ) names
      );
    in
    if values == [ ] then fallback else builtins.head values;

  stringListField =
    attrs: names: fallback:
    let
      values = lib.concatMap (
        name:
        if builtins.isAttrs attrs && builtins.hasAttr name attrs then
          (
            if builtins.isString attrs.${name} then
              [ attrs.${name} ]
            else if builtins.isList attrs.${name} then
              lib.filter builtins.isString attrs.${name}
            else
              [ ]
          )
        else
          [ ]
      ) names;
    in
    if values == [ ] then fallback else lib.unique values;

  safeStem = name: builtins.replaceStrings [ "/" ":" " " ] [ "-" "-" "-" ] name;
}
