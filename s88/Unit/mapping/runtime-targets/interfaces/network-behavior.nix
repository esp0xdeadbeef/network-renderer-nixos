{ lib, common }:

interfaces:
let
  names = common.sortedAttrNames interfaces;
  classFor =
    name:
    let ifaceClass = interfaces.${name}.interfaceClass or { };
    in if builtins.isAttrs ifaceClass then ifaceClass else { };
  hasClass = flag: name: (classFor name).${flag} or false;
  hasSourceKind =
    kind: name:
    (interfaces.${name}.sourceKind or null) == kind;
  isSelector = lib.any (hasClass "edgeFacing") names && lib.any (hasClass "fabricFacing") names;
  isUpstreamSelector = lib.any (hasClass "coreFacing") names && lib.any (hasClass "exitFacing") names;
  isPolicy = lib.any (hasClass "fabricFacing") names && lib.any (hasClass "exitFacing") names;
  isAccessGateway = lib.any (hasClass "edgeFacing") names && lib.any (hasSourceKind "tenant") names;
in
{
  inherit isSelector isUpstreamSelector isPolicy isAccessGateway;
  keepInterfaceRoutesInMain = !(isSelector || isUpstreamSelector || isPolicy || isAccessGateway);
}
