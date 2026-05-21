{ isSelector
, isUpstreamSelector
, isDownstreamSelectorPolicyInterface
, isUpstreamSelectorPolicyInterface
,
}:

interfaceName: tableId: sourceIfNames:
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
in
if sourceIfNames == [ ] then
  [ ]
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
