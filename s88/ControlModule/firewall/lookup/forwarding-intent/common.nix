{ lib }:

let
  asList =
    value:
    if value == null then [ ] else if builtins.isList value then value else [ value ];

  asStringList = value: lib.filter builtins.isString (asList value);

  sortedStrings =
    values:
    lib.sort builtins.lessThan (
      lib.unique (lib.filter (value: builtins.isString value && value != "") values)
    );

  boolOrFalse = value: if builtins.isBool value then value else false;

  attrPathOrNull =
    attrs: path:
    if path == [ ] then
      attrs
    else if !builtins.isAttrs attrs then
      null
    else
      let
        key = builtins.head path;
        rest = builtins.tail path;
      in
      if builtins.hasAttr key attrs then attrPathOrNull attrs.${key} rest else null;

  valuesFromPaths =
    { roots, paths }:
    lib.concatMap (
      path:
      lib.concatMap (
        root:
        let value = attrPathOrNull root path;
        in if value == null then [ ] else [ value ]
      ) roots
    ) paths;

  boolLikeFromPaths =
    { roots, paths }:
    let
      values = lib.concatMap (
        value:
        if builtins.isBool value then
          [ value ]
        else if builtins.isAttrs value && value ? enable && builtins.isBool value.enable then
          [ value.enable ]
        else
          [ ]
      ) (valuesFromPaths { inherit roots paths; });
    in
    if values == [ ] then null else builtins.head values;

  firstAttrsFromPaths =
    { roots, paths }:
    let values = lib.filter builtins.isAttrs (valuesFromPaths { inherit roots paths; });
    in if values == [ ] then { } else builtins.head values;

  stringListFromPaths =
    { roots, paths }:
    sortedStrings (lib.concatMap asStringList (valuesFromPaths { inherit roots paths; }));

  lastStringSegment =
    separator: value:
    let
      parts = lib.splitString separator value;
      count = builtins.length parts;
    in
    if count == 0 then null else builtins.elemAt parts (count - 1);

  attrOr =
    attrs: name: fallback:
    if builtins.isAttrs attrs && builtins.hasAttr name attrs then attrs.${name} else fallback;
in
{
  inherit
    asList
    asStringList
    sortedStrings
    boolOrFalse
    attrPathOrNull
    valuesFromPaths
    boolLikeFromPaths
    firstAttrsFromPaths
    stringListFromPaths
    lastStringSegment
    attrOr
    ;
}
