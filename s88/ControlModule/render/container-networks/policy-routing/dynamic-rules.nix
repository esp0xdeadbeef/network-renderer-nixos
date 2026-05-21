{
  lib,
  isSelector,
  isUpstreamSelector,
  isDownstreamSelectorPolicyInterface,
  isUpstreamSelectorPolicyInterface,
}:

interfaceName: tableId: sourceIfNames: sourceFiles:
let
  tableRule = {
    interfaceName = interfaceName;
    priority = tableId;
    table = tableId;
  };
  mainFallbackRule = {
    interfaceName = interfaceName;
    priority = 10000 + tableId;
    table = 254;
    suppressPrefixLength = 0;
  };
  mainFirstRule = mainFallbackRule // {
    priority = tableId;
  };
  tableSecondRule = tableRule // {
    priority = 10000 + tableId;
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
if sourceIfNames == [ ] || sourceFiles == [ ] then
  [ ]
else
  lib.concatMap (
    source:
    map (
      rule:
      rule
      // {
        inherit (source) family sourceFile;
      }
    ) rulesForMode
  ) sourceFiles
