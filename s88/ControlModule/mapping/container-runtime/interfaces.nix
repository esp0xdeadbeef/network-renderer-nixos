{
  lib,
  lookup,
}:

let
  hostNaming = import ../../../../lib/host-naming.nix { inherit lib; };

  interfaceNameMaxLength = 15;

  validInterfaceName =
    name: builtins.isString name && name != "" && builtins.stringLength name <= interfaceNameMaxLength;

  sourceKindForInterface =
    iface:
    if
      iface ? connectivity
      && builtins.isAttrs iface.connectivity
      && iface.connectivity ? sourceKind
      && builtins.isString iface.connectivity.sourceKind
    then
      iface.connectivity.sourceKind
    else if iface ? sourceKind && builtins.isString iface.sourceKind then
      iface.sourceKind
    else
      null;

  attachTargetForInterface =
    {
      unitName,
      ifName,
      iface,
    }:
    let
      matches = lib.filter (
        target:
        (target.unitName or null) == unitName
        && (
          (target.ifName or null) == ifName
          || ((target.renderedIfName or null) == (iface.renderedIfName or null))
          || ((target.interface.renderedIfName or null) == (iface.renderedIfName or null))
          || ((target.hostBridgeName or null) == (iface.hostBridge or null))
        )
      ) lookup.localAttachTargets;
    in
    if builtins.length matches == 1 then
      builtins.head matches
    else if builtins.hasAttr (iface.hostBridge or "") lookup.bridgeNameMap then
      {
        renderedHostBridgeName = lookup.bridgeNameMap.${iface.hostBridge};
        assignedUplinkName = null;
        identity = { };
      }
    else
      throw ''
        s88/CM/network/mapping/container-runtime.nix: could not resolve rendered host bridge for unit '${unitName}', interface '${ifName}'

        iface.hostBridge:
        ${builtins.toJSON (iface.hostBridge or null)}

        available bridgeNameMap keys:
        ${builtins.toJSON (lookup.sortedAttrNames lookup.bridgeNameMap)}

        attachTargets:
        ${builtins.toJSON lookup.localAttachTargets}
      '';

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

  interfaceNameFromAttachTarget =
    attachTarget:
    if
      attachTarget ? identity
      && builtins.isAttrs attachTarget.identity
      && attachTarget.identity ? portName
      && validInterfaceName attachTarget.identity.portName
    then
      attachTarget.identity.portName
    else
      null;

  interfaceNameFromUpstream =
    iface:
    if
      iface ? connectivity
      && builtins.isAttrs iface.connectivity
      && iface.connectivity ? upstream
      && validInterfaceName iface.connectivity.upstream
    then
      iface.connectivity.upstream
    else
      null;

  effectiveInterfaceNameForInterface =
    {
      ifName,
      iface,
      attachTarget,
    }:
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

  normalizedInterfacesForUnit =
    {
      unitName,
      containerName,
      interfaces,
    }:
    let
      entries = map (
        ifName:
        let
          iface = interfaces.${ifName};
          attachTarget = attachTargetForInterface { inherit unitName ifName iface; };
          sourceKind = sourceKindForInterface iface;

          desiredInterfaceName = effectiveInterfaceNameForInterface {
            inherit ifName iface attachTarget;
          };

          hostVethName = hostNaming.shorten "${containerName}-${desiredInterfaceName}";
        in
        {
          inherit ifName;
          value = {
            inherit
              ifName
              sourceKind
              hostVethName
              desiredInterfaceName
              ;
            renderedIfName = iface.renderedIfName or ifName;
            containerInterfaceName = hostVethName;
            addresses = iface.addresses or [ ];
            routes = iface.routes or [ ];
            renderedHostBridgeName = attachTarget.renderedHostBridgeName;
            assignedUplinkName = attachTarget.assignedUplinkName or null;
            hostInterfaceName = hostVethName;
            connectivity = iface.connectivity or { };
            backingRef = iface.backingRef or { };
            hostBridge = iface.hostBridge or null;
            identity = attachTarget.identity or { };
            upstream =
              if
                iface ? connectivity
                && builtins.isAttrs iface.connectivity
                && iface.connectivity ? upstream
                && builtins.isString iface.connectivity.upstream
              then
                iface.connectivity.upstream
              else
                null;
          };
        }
      ) (lookup.sortedAttrNames interfaces);

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
      builtins.listToAttrs (
        map (entry: {
          name = entry.ifName;
          value = entry.value;
        }) entries
      )
    );

  vethsForInterfaces =
    interfaces:
    builtins.listToAttrs (
      map (
        ifName:
        let
          iface = interfaces.${ifName};
          hostVethName =
            if iface ? hostVethName && builtins.isString iface.hostVethName then
              iface.hostVethName
            else if iface ? hostInterfaceName && builtins.isString iface.hostInterfaceName then
              iface.hostInterfaceName
            else if iface ? containerInterfaceName && builtins.isString iface.containerInterfaceName then
              iface.containerInterfaceName
            else
              ifName;
        in
        {
          name = hostVethName;
          value = {
            hostBridge = iface.renderedHostBridgeName;
          };
        }
      ) (lookup.sortedAttrNames interfaces)
    );
in
{
  inherit
    sourceKindForInterface
    attachTargetForInterface
    normalizedInterfacesForUnit
    vethsForInterfaces
    ;
}
