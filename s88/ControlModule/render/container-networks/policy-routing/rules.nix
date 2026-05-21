{
  lib,
  isSelector,
  isUpstreamSelector,
  isDownstreamSelectorPolicyInterface,
  isUpstreamSelectorPolicyInterface,
}:

interfaceName: tableId: sourceIfNames: sourcePrefixes:
let
  tableRule = {
    Family = "both";
    IncomingInterface = interfaceName;
    Priority = tableId;
    Table = tableId;
  };
  mainFallbackRule = {
    Family = "both";
    IncomingInterface = interfaceName;
    Priority = 10000 + tableId;
    Table = 254;
    SuppressPrefixLength = 0;
  };
  mainFirstRule = mainFallbackRule // {
    Priority = tableId;
  };
  tableSecondRule = tableRule // {
    Priority = 10000 + tableId;
  };
  scoped = sourcePrefixes != [ ];
  scopeRule =
    prefix: rule:
    rule
    // {
      Family = if (prefix.family or 4) == 6 then "ipv6" else "ipv4";
      From = prefix.prefix;
    };
  rulesForMode =
    if
      (isUpstreamSelector && isUpstreamSelectorPolicyInterface interfaceName)
      || (isSelector && isDownstreamSelectorPolicyInterface interfaceName)
    then
      [
        tableRule
        mainFallbackRule
      ]
    else
      [
        mainFirstRule
        tableSecondRule
      ];
in
if sourceIfNames == [ ] then
  [ ]
else if scoped then
  lib.concatMap (prefix: map (scopeRule prefix) rulesForMode) sourcePrefixes
else if
  (isUpstreamSelector && isUpstreamSelectorPolicyInterface interfaceName)
  || (isSelector && isDownstreamSelectorPolicyInterface interfaceName)
then
  [
    tableRule
    mainFallbackRule
  ]
else
  [
    mainFirstRule
    tableSecondRule
  ]
