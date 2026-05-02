{ lib }:

rec {
  sortedAttrNames = attrs: lib.sort builtins.lessThan (builtins.attrNames attrs);

  stringList =
    value:
    if value == null then
      [ ]
    else if builtins.isString value then
      [ value ]
    else if builtins.isList value then
      lib.filter builtins.isString value
    else
      [ ];

  routeList =
    value:
    if value == null then [ ] else if builtins.isList value then value else [ value ];

  normalizeRoutes =
    routes:
    if builtins.isList routes then
      (if routes == null then [ ] else routes)
    else
      let routeTree = if builtins.isAttrs routes then routes else { };
      in (routeList (routeTree.ipv4 or [ ])) ++ (routeList (routeTree.ipv6 or [ ]));

  identityPartToString =
    value:
    if value == null then
      null
    else if builtins.isString value then
      value
    else if builtins.isInt value || builtins.isFloat value || builtins.isBool value then
      builtins.toJSON value
    else if builtins.isList value || builtins.isAttrs value then
      builtins.toJSON value
    else
      builtins.toString value;
}
