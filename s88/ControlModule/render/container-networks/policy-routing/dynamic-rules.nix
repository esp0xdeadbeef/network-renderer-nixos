{
  lib,
  renderedInterfaceNames,
  isSelector,
  isUpstreamSelector,
  isDownstreamSelectorPolicyInterface,
  isUpstreamSelectorPolicyInterface,
}:

interfaceName: tableId: sourceIfNames: sourceFiles:
let
  ingressInterfaces =
    lib.unique (
      map (name: renderedInterfaceNames.${name} or name) (
        if sourceIfNames == [ ] then [ ] else sourceIfNames
      )
    );
  rulesForIngress =
    incomingInterface:
    [
      {
        interfaceName = incomingInterface;
        priority = tableId;
        table = tableId;
      }
      {
        interfaceName = incomingInterface;
        priority = 10000 + tableId;
        table = 254;
        suppressPrefixLength = 0;
      }
    ];
  rulesForMode = lib.concatMap rulesForIngress ingressInterfaces;
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
