{ lib
, renderedInterfaceNames
, isSelector
, isUpstreamSelector
, isDownstreamSelectorPolicyInterface
, isUpstreamSelectorPolicyInterface
,
}:

interfaceName: tableId: sourceIfNames: sourcePrefixes: destinationPrefixes:
let
  ingressInterfaces =
    lib.unique (
      map (name: renderedInterfaceNames.${name} or name) (
        if sourceIfNames == [ ] then [ ] else sourceIfNames
      )
    );
  tableRuleFor = incomingInterface: {
    Family = "both";
    IncomingInterface = incomingInterface;
    Priority = tableId;
    Table = tableId;
  };
  mainFallbackRuleFor = incomingInterface: {
    Family = "both";
    IncomingInterface = incomingInterface;
    Priority = 10000 + tableId;
    Table = 254;
    SuppressPrefixLength = 0;
  };
  scoped = sourcePrefixes != [ ];
  destinationScoped = destinationPrefixes != [ ];
  scopeRule =
    prefix: rule:
    rule
    // {
      Family = if (prefix.family or 4) == 6 then "ipv6" else "ipv4";
      From = prefix.prefix;
    };
  destinationScopeRule =
    prefix: rule:
    rule
    // {
      Family = if (prefix.family or 4) == 6 then "ipv6" else "ipv4";
      To = prefix.prefix;
    };
  rulesForIngress =
    incomingInterface:
    let
      tableRule = tableRuleFor incomingInterface;
      mainFallbackRule = mainFallbackRuleFor incomingInterface;
    in
    [
      tableRule
      mainFallbackRule
    ];
  unscopedRules = lib.concatMap rulesForIngress ingressInterfaces;
in
if sourceIfNames == [ ] then
  [ ]
else if destinationScoped then
  lib.concatMap (prefix: map (destinationScopeRule prefix) unscopedRules) destinationPrefixes
else if scoped then
  lib.concatMap
    (
      prefix:
      (map (scopeRule prefix) unscopedRules) ++ (map (destinationScopeRule prefix) unscopedRules)
    )
    sourcePrefixes
else
  unscopedRules
