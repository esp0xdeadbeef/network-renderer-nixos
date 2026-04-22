{
  lib,
  lookup,
}:

let
  interfaceNameMaxLength = 15;

  semanticTokenAliases = {
    upstream = "up";
    downstream = "down";
    selector = "sel";
    policy = "pol";
    access = "acc";
    branch = "branch";
    client = "client";
    admin = "admin";
    mgmt = "mgmt";
    management = "mgmt";
    tenant = "tenant";
    transit = "transit";
    overlay = "ovly";
    east = "e";
    west = "w";
    north = "n";
    south = "s";
    core = "core";
    dmz = "dmz";
    wan = "wan";
    uplink = "up";
    isp = "isp";
  };

  nonDistinctContainerTokens = [
    "s"
    "router"
    "network"
    "container"
  ];

  validInterfaceName =
    name: builtins.isString name && name != "" && builtins.stringLength name <= interfaceNameMaxLength;

  firstValidInterfaceName =
    names:
    let
      validNames = lib.filter validInterfaceName names;
    in
    if validNames != [ ] then builtins.head validNames else null;

  aliasToken =
    token: if builtins.hasAttr token semanticTokenAliases then semanticTokenAliases.${token} else token;

  truncateToken =
    maxLen: token:
    let
      tokenLen = builtins.stringLength token;
    in
    if tokenLen <= maxLen then token else builtins.substring 0 maxLen token;

  semanticBaseInterfaceName =
    desiredInterfaceName:
    let
      rawTokens = lib.filter (token: token != "") (lib.splitString "-" desiredInterfaceName);
      aliasedTokens = map aliasToken rawTokens;
      candidateNames = [
        desiredInterfaceName
        (lib.concatStringsSep "-" aliasedTokens)
        (lib.concatStringsSep "-" (map (truncateToken 4) aliasedTokens))
        (lib.concatStringsSep "-" (map (truncateToken 3) aliasedTokens))
        (lib.concatStringsSep "" (map (truncateToken 1) aliasedTokens))
        (builtins.substring 0 interfaceNameMaxLength desiredInterfaceName)
      ];
      selected = firstValidInterfaceName candidateNames;
    in
    if selected != null then
      selected
    else
      throw ''
        s88/CM/network/mapping/container-runtime.nix: could not derive a valid container interface name

        desiredInterfaceName:
        ${builtins.toJSON desiredInterfaceName}
      '';

  semanticTokensForName =
    name: map aliasToken (lib.filter (token: token != "") (lib.splitString "-" name));

  compactSemanticName =
    {
      name,
      maxLen,
      fallback,
      removeTokens ? [ ],
    }:
    let
      allTokens = semanticTokensForName name;
      preferredTokens = lib.filter (token: !(builtins.elem token removeTokens)) allTokens;
      selectedTokens = if preferredTokens != [ ] then preferredTokens else allTokens;
      compact = lib.concatStringsSep "" (map (truncateToken 3) selectedTokens);
      normalized = if compact != "" then compact else fallback;
    in
    if builtins.stringLength normalized <= maxLen then
      normalized
    else
      builtins.substring 0 maxLen normalized;

  semanticHostVethBaseName =
    {
      containerName,
      desiredInterfaceName,
      adapterName ? null,
    }:
    let
      adapterTokenSource =
        if builtins.isString adapterName && adapterName != "" then adapterName else desiredInterfaceName;
      containerToken = compactSemanticName {
        name = containerName;
        maxLen = 4;
        fallback = "unit";
        removeTokens = nonDistinctContainerTokens;
      };
      interfaceToken = compactSemanticName {
        name = adapterTokenSource;
        maxLen = 6;
        fallback = "if";
      };

      hashSuffix = builtins.substring 0 3 (
        builtins.hashString "sha256" "${containerName}:${desiredInterfaceName}:${adapterTokenSource}"
      );
    in
    "${containerToken}-${interfaceToken}-${hashSuffix}";

  uniqueInterfaceNameCandidate =
    baseName: index:
    if index <= 1 then
      baseName
    else
      let
        suffix = "-${toString index}";
        prefixLen = interfaceNameMaxLength - builtins.stringLength suffix;
        prefix =
          if prefixLen > 0 then builtins.substring 0 prefixLen baseName else builtins.substring 0 1 baseName;
      in
      "${prefix}${suffix}";

  resolveUniqueInterfaceName =
    {
      baseName,
      usedNames,
      index ? 1,
    }:
    let
      candidate = uniqueInterfaceNameCandidate baseName index;
    in
    if !(builtins.hasAttr candidate usedNames) then
      candidate
    else
      resolveUniqueInterfaceName {
        inherit baseName usedNames;
        index = index + 1;
      };

  assignUniqueContainerInterfaceNames =
    entries:
    let
      resolved =
        builtins.foldl'
          (
            acc: entry:
            let
              baseName = entry.value.containerInterfaceBaseName;
              resolvedName = resolveUniqueInterfaceName {
                inherit baseName;
                usedNames = acc.usedNames;
              };
            in
            {
              usedNames = acc.usedNames // {
                ${resolvedName} = true;
              };
              entries = acc.entries ++ [
                (
                  entry
                  // {
                    value = entry.value // {
                      containerInterfaceName = resolvedName;
                    };
                  }
                )
              ];
            }
          )
          {
            usedNames = { };
            entries = [ ];
          }
          entries;
    in
    resolved.entries;

  assignUniqueHostVethNames =
    entries:
    let
      resolved =
        builtins.foldl'
          (
            acc: entry:
            if entry.value.usePrimaryHostBridge or false then
              {
                usedNames = acc.usedNames;
                entries = acc.entries ++ [ entry ];
              }
            else
              let
                baseName = entry.value.hostVethBaseName;
                resolvedName = resolveUniqueInterfaceName {
                  inherit baseName;
                  usedNames = acc.usedNames;
                };
              in
              {
                usedNames = acc.usedNames // {
                  ${resolvedName} = true;
                };
                entries = acc.entries ++ [
                  (
                    entry
                    // {
                      value = entry.value // {
                        hostVethName = resolvedName;
                        hostInterfaceName = resolvedName;
                      };
                    }
                  )
                ];
              }
          )
          {
            usedNames = { };
            entries = [ ];
          }
          entries;
    in
    resolved.entries;

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
      bridgeEligibleWanIfNames = lib.filter (
        ifName:
        let
          iface = interfaces.${ifName};
          attachTarget = attachTargetForInterface { inherit unitName ifName iface; };
        in
        sourceKindForInterface iface == "wan"
        && attachTarget ? renderedHostBridgeName
        && builtins.isString attachTarget.renderedHostBridgeName
      ) (lookup.sortedAttrNames interfaces);

      primaryHostBridgeIfName =
        if builtins.length bridgeEligibleWanIfNames == 1 then
          builtins.head bridgeEligibleWanIfNames
        else
          null;

      entriesRaw = map (
        ifName:
        let
          iface = interfaces.${ifName};
          attachTarget = attachTargetForInterface { inherit unitName ifName iface; };
          sourceKind = sourceKindForInterface iface;

          desiredInterfaceName = effectiveInterfaceNameForInterface {
            inherit ifName iface attachTarget;
          };

          usePrimaryHostBridge = primaryHostBridgeIfName == ifName;
        in
        {
          inherit ifName;
          value = {
            inherit
              ifName
              sourceKind
              desiredInterfaceName
              usePrimaryHostBridge
              ;
            hostVethBaseName = semanticHostVethBaseName {
              inherit containerName desiredInterfaceName;
              adapterName = if iface ? adapterName then iface.adapterName else null;
            };
            hostVethName = if usePrimaryHostBridge then null else null;
            renderedIfName = iface.renderedIfName or ifName;
            containerInterfaceBaseName =
              if usePrimaryHostBridge then "eth0" else semanticBaseInterfaceName desiredInterfaceName;
            containerInterfaceName = if usePrimaryHostBridge then "eth0" else null;
            adapterName =
              if iface ? adapterName && builtins.isString iface.adapterName then iface.adapterName else null;
            addresses = iface.addresses or [ ];
            routes = iface.routes or [ ];
            renderedHostBridgeName = attachTarget.renderedHostBridgeName;
            assignedUplinkName = attachTarget.assignedUplinkName or null;
            hostInterfaceName = if usePrimaryHostBridge then null else null;
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
      builtins.listToAttrs (
        map (entry: {
          name = entry.ifName;
          value = entry.value;
        }) entries
      )
    );

  vethsForInterfaces =
    interfaces:
    let
      entries = map (
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
        if iface.usePrimaryHostBridge or false then
          null
        else
          {
            name = hostVethName;
            value = {
              hostBridge = iface.renderedHostBridgeName;
            };
          }
      ) (lookup.sortedAttrNames interfaces);
    in
    builtins.listToAttrs (lib.filter (entry: entry != null) entries);
in
{
  inherit
    sourceKindForInterface
    attachTargetForInterface
    normalizedInterfacesForUnit
    vethsForInterfaces
    ;
}
