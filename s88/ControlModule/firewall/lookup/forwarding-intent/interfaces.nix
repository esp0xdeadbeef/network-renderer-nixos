{ lib, common, interfaces }:

let
  inherit (common)
    asStringList
    sortedStrings
    boolLikeFromPaths
    lastStringSegment
    ;

  actualNameForInterface =
    ifName: iface:
    if iface ? containerInterfaceName && builtins.isString iface.containerInterfaceName && iface.containerInterfaceName != "" then
      iface.containerInterfaceName
    else if iface ? interfaceName && builtins.isString iface.interfaceName && iface.interfaceName != "" then
      iface.interfaceName
    else if iface ? hostInterfaceName && builtins.isString iface.hostInterfaceName && iface.hostInterfaceName != "" then
      iface.hostInterfaceName
    else if iface ? renderedIfName && builtins.isString iface.renderedIfName && iface.renderedIfName != "" then
      iface.renderedIfName
    else if iface ? ifName && builtins.isString iface.ifName && iface.ifName != "" then
      iface.ifName
    else
      ifName;

  semanticInterfaceFor =
    iface:
    if iface ? semanticInterface && builtins.isAttrs iface.semanticInterface then
      iface.semanticInterface
    else if iface ? semantic && builtins.isAttrs iface.semantic then
      iface.semantic
    else
      { };

  sourceKindForInterface =
    iface: semanticInterface:
    if semanticInterface ? kind && builtins.isString semanticInterface.kind then
      semanticInterface.kind
    else if iface ? sourceKind && builtins.isString iface.sourceKind then
      iface.sourceKind
    else if iface ? connectivity && builtins.isAttrs iface.connectivity && iface.connectivity ? sourceKind then
      iface.connectivity.sourceKind
    else
      null;

  rolePaths = {
    localAdapter = [ [ "localAdapter" ] [ "local" ] [ "tenantFacing" ] [ "forwarding" "localAdapter" ] [ "forwarding" "participation" "localAdapter" ] [ "forwarding" "traversal" "localAdapter" ] [ "roles" "localAdapter" ] [ "roles" "tenantFacing" ] ];
    uplink = [ [ "uplink" ] [ "upstream" ] [ "forwarding" "uplink" ] [ "forwarding" "participation" "uplink" ] [ "roles" "uplink" ] [ "roles" "upstream" ] [ "roles" "wan" ] ];
    transit = [ [ "transit" ] [ "forwarding" "transit" ] [ "forwarding" "participation" "transit" ] [ "forwarding" "participatesInTraversal" ] [ "roles" "transit" ] ];
    exitEligible = [ [ "exitEligible" ] [ "egress" "exitEligible" ] [ "egress" "upstreamSelectionEligible" ] [ "forwarding" "exitEligible" ] ];
    natEnabled = [ [ "nat" ] [ "nat" "enable" ] [ "masquerade" ] [ "masquerade" "enable" ] [ "egress" "nat" ] [ "egress" "nat" "enable" ] [ "egress" "masquerade" ] [ "egress" "masquerade" "enable" ] ];
    clampMss = [ [ "clampMss" ] [ "tcpMssClamp" ] [ "egress" "clampMss" ] [ "egress" "tcpMssClamp" ] ];
    wan = [ [ "wan" ] [ "roles" "wan" ] ];
  };

  rawInterfaceEntries = map (
    ifName:
    let
      iface = interfaces.${ifName};
      semanticInterface = semanticInterfaceFor iface;
      backingRef = if iface ? backingRef && builtins.isAttrs iface.backingRef then iface.backingRef else { };
      backingRefIdTail =
        if backingRef ? id && builtins.isString backingRef.id then lastStringSegment "::" backingRef.id else null;
    in
    {
      key = ifName;
      name = actualNameForInterface ifName iface;
      inherit iface semanticInterface backingRef;
      sourceKind = sourceKindForInterface iface semanticInterface;
      refs = sortedStrings ([
        ifName
        (actualNameForInterface ifName iface)
        (iface.renderedIfName or null)
        (iface.interfaceName or null)
        (iface.containerInterfaceName or null)
        (iface.hostInterfaceName or null)
        (iface.ifName or null)
        (iface.realizationPortName or null)
        (iface.sourceInterface or null)
        (iface.connectivity.upstream or null)
        (backingRef.name or null)
        backingRefIdTail
        (backingRef.kind or null)
      ] ++ (asStringList (iface.interfaceAliases or [ ])));
    }
  ) (lib.sort builtins.lessThan (builtins.attrNames interfaces));

  interfaceEntries = map (
    entry:
    let roots = [ entry.iface entry.semanticInterface ];
    in
    entry // {
      explicit = {
        explicitLocalAdapter = boolLikeFromPaths { inherit roots; paths = rolePaths.localAdapter; };
        explicitUplink = boolLikeFromPaths { inherit roots; paths = rolePaths.uplink; };
        explicitTransit = boolLikeFromPaths { inherit roots; paths = rolePaths.transit; };
        explicitExitEligible = boolLikeFromPaths { inherit roots; paths = rolePaths.exitEligible; };
        explicitNatEnabled = boolLikeFromPaths { inherit roots; paths = rolePaths.natEnabled; };
        explicitClampMss = boolLikeFromPaths { inherit roots; paths = rolePaths.clampMss; };
        explicitWan = boolLikeFromPaths { inherit roots; paths = rolePaths.wan; };
      };
    }
  ) rawInterfaceEntries;

  namesForInterfaceToken =
    token:
    sortedStrings (
      map (entry: entry.name) (lib.filter (entry: builtins.elem token entry.refs) interfaceEntries)
    );

  resolveInterfaceTokens =
    tokens:
    sortedStrings (
      lib.concatMap (
        token:
        let matches = namesForInterfaceToken token;
        in if matches != [ ] then matches else [ token ]
      ) (asStringList tokens)
    );
in
{
  inherit
    interfaceEntries
    resolveInterfaceTokens
    ;
  interfaceNames = sortedStrings (map (entry: entry.name) interfaceEntries);
}
