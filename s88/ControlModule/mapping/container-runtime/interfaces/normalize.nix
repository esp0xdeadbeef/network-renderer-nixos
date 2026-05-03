{
  lib,
  lookup,
  naming,
  attach,
}:

let
  inherit
    (naming)
    semanticBaseInterfaceName
    semanticHostVethBaseName
    assignUniqueContainerInterfaceNames
    assignUniqueHostVethNames
    ;
  inherit
    (attach)
    sourceKindForInterface
    attachTargetForInterface
    interfaceNameFromAttachTarget
    interfaceNameFromUpstream
    ;

  isKernelStyleInterfaceName =
    name:
    builtins.isString name
    && (
      builtins.match "eth[0-9]+" name != null
      || builtins.match "ens[0-9]+" name != null
      || builtins.match "eno[0-9]+" name != null
      || builtins.match "enp[0-9s.]+" name != null
      || builtins.match "enx[0-9a-fA-F]+" name != null
      || name == "lo"
    );

  addressListForInterface =
    iface:
    let
      existing = if builtins.isList (iface.addresses or null) then iface.addresses else [ ];
      addr4 = if builtins.isString (iface.addr4 or null) then [ iface.addr4 ] else [ ];
      addr6 = if builtins.isString (iface.addr6 or null) then [ iface.addr6 ] else [ ];
    in
    lib.unique (existing ++ addr4 ++ addr6);

  routeListForInterface =
    iface:
    let
      routes = iface.routes or [ ];
    in
    if builtins.isList routes then
      routes
    else if builtins.isAttrs routes then
      (if builtins.isList (routes.ipv4 or null) then routes.ipv4 else [ ])
      ++ (if builtins.isList (routes.ipv6 or null) then routes.ipv6 else [ ])
    else
      [ ];

  effectiveInterfaceNameForInterface =
    { ifName, iface, attachTarget }:
    let
      renderedIfName = iface.renderedIfName or ifName;
      sourceKind = sourceKindForInterface iface;
      upstreamName = interfaceNameFromUpstream iface;
      attachName = interfaceNameFromAttachTarget attachTarget;
    in
    if sourceKind == "wan" && upstreamName != null then
      upstreamName
    else if isKernelStyleInterfaceName renderedIfName && attachName != null then
      attachName
    else
      renderedIfName;

  entryFor =
    { unitName, containerName, interfaces }:
    ifName:
    let
      iface = interfaces.${ifName};
      attachTarget = attachTargetForInterface { inherit unitName ifName iface; };
      sourceKind = sourceKindForInterface iface;
      desiredInterfaceName = effectiveInterfaceNameForInterface { inherit ifName iface attachTarget; };
      bridgeEligibleWanIfNames = lib.filter (
        name:
        let
          candidateIface = interfaces.${name};
          candidateAttach = attachTargetForInterface { inherit unitName; ifName = name; iface = candidateIface; };
        in
        sourceKindForInterface candidateIface == "wan"
        && builtins.isString (candidateAttach.renderedHostBridgeName or null)
      ) (lookup.sortedAttrNames interfaces);
      primaryHostBridgeIfName = if builtins.length bridgeEligibleWanIfNames == 1 then builtins.head bridgeEligibleWanIfNames else null;
      usePrimaryHostBridge = primaryHostBridgeIfName == ifName;
      realizationPortName =
        if attachTarget ? identity && builtins.isAttrs attachTarget.identity && builtins.isString (attachTarget.identity.portName or null) then
          attachTarget.identity.portName
        else
          null;
      interfaceAliases = lib.unique (
        lib.filter builtins.isString [
          ifName
          (iface.ifName or null)
          (iface.renderedIfName or null)
          desiredInterfaceName
          realizationPortName
          (iface.sourceInterface or null)
          (iface.backingRef.name or null)
        ]
      );
    in
    {
      inherit ifName;
      value = {
        inherit ifName sourceKind desiredInterfaceName usePrimaryHostBridge realizationPortName interfaceAliases;
        hostVethBaseName = semanticHostVethBaseName {
          inherit containerName desiredInterfaceName;
          adapterName = if iface ? adapterName then iface.adapterName else null;
        };
        hostVethName = if usePrimaryHostBridge then null else null;
        renderedIfName = iface.renderedIfName or ifName;
        containerInterfaceBaseName = if usePrimaryHostBridge then "eth0" else semanticBaseInterfaceName desiredInterfaceName;
        containerInterfaceName = if usePrimaryHostBridge then "eth0" else null;
        adapterName = if iface ? adapterName && builtins.isString iface.adapterName then iface.adapterName else null;
        addresses = addressListForInterface iface;
        routes = routeListForInterface iface;
        renderedHostBridgeName = attachTarget.renderedHostBridgeName;
        assignedUplinkName = attachTarget.assignedUplinkName or null;
        hostInterfaceName = if usePrimaryHostBridge then null else null;
        connectivity = iface.connectivity or { };
        backingRef = iface.backingRef or { };
        hostBridge = iface.hostBridge or null;
        identity = attachTarget.identity or { };
        upstream =
          if iface ? connectivity && builtins.isAttrs iface.connectivity && builtins.isString (iface.connectivity.upstream or null) then
            iface.connectivity.upstream
          else
            null;
      };
    };
in
{
  normalizedInterfacesForUnit =
    { unitName, containerName, interfaces }:
    let
      entriesRaw = map (entryFor { inherit unitName containerName interfaces; }) (lookup.sortedAttrNames interfaces);
      entries = assignUniqueContainerInterfaceNames (assignUniqueHostVethNames entriesRaw);
      interfaceNames = map (entry: entry.value.containerInterfaceName) entries;
      _validateUniqueInterfaceNames =
        if builtins.length interfaceNames == builtins.length (lib.unique interfaceNames) then
          true
        else
          throw ''
            s88/CM/network/mapping/container-runtime.nix: effective container interface names are not unique for unit '${unitName}'

            interface names:
            ${builtins.toJSON interfaceNames}

            interfaces:
            ${builtins.toJSON interfaces}
          '';
    in
    builtins.seq _validateUniqueInterfaceNames (
      builtins.listToAttrs (map (entry: { name = entry.ifName; value = entry.value; }) entries)
    );
}
