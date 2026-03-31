{
  lib,
  hostPlan,
}:

let
  hostNaming = import ../../../lib/host-naming.nix { inherit lib; };

  sortedAttrNames = attrs: lib.sort builtins.lessThan (builtins.attrNames attrs);

  interfaceNameMaxLength = 15;

  validInterfaceName =
    name: builtins.isString name && name != "" && builtins.stringLength name <= interfaceNameMaxLength;

  normalizedRuntimeTargets = hostPlan.normalizedRuntimeTargets or { };
  selectedUnits = hostPlan.selectedUnits or [ ];
  selectedRoles = hostPlan.selectedRoles or { };
  unitRoles = hostPlan.unitRoles or { };
  localAttachTargets = hostPlan.localAttachTargets or [ ];
  bridgeNameMap = hostPlan.bridgeNameMap or { };
  deploymentHostName = hostPlan.deploymentHostName or null;
  hostContext = hostPlan.resolvedHostContext or { };

  runtimeTargetForUnit =
    unitName:
    if builtins.hasAttr unitName normalizedRuntimeTargets then
      normalizedRuntimeTargets.${unitName}
    else
      throw ''
        s88/CM/network/mapping/container-runtime.nix: missing normalized runtime target for unit '${unitName}'
      '';

  runtimeTargetIdForUnit =
    unitName:
    let
      runtimeTarget = runtimeTargetForUnit unitName;
    in
    if runtimeTarget ? runtimeTargetId && builtins.isString runtimeTarget.runtimeTargetId then
      runtimeTarget.runtimeTargetId
    else if
      runtimeTarget ? logicalNode
      && builtins.isAttrs runtimeTarget.logicalNode
      && runtimeTarget.logicalNode ? name
      && builtins.isString runtimeTarget.logicalNode.name
    then
      runtimeTarget.logicalNode.name
    else
      unitName;

  roleForUnit = unitName: if builtins.hasAttr unitName unitRoles then unitRoles.${unitName} else null;

  roleConfigForUnit =
    unitName:
    let
      roleName = roleForUnit unitName;
    in
    if roleName != null && builtins.hasAttr roleName selectedRoles then
      selectedRoles.${roleName}
    else
      { };

  containerConfigForUnit =
    unitName:
    let
      roleConfig = roleConfigForUnit unitName;
    in
    if roleConfig ? container && builtins.isAttrs roleConfig.container then
      roleConfig.container
    else
      { };

  containerEnabledForUnit =
    unitName:
    let
      containerConfig = containerConfigForUnit unitName;
    in
    containerConfig ? enable && (containerConfig.enable or false);

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
      ) localAttachTargets;
    in
    if builtins.length matches == 1 then
      builtins.head matches
    else if builtins.hasAttr (iface.hostBridge or "") bridgeNameMap then
      {
        renderedHostBridgeName = bridgeNameMap.${iface.hostBridge};
        assignedUplinkName = null;
        identity = { };
      }
    else
      throw ''
        s88/CM/network/mapping/container-runtime.nix: could not resolve rendered host bridge for unit '${unitName}', interface '${ifName}'

        iface.hostBridge:
        ${builtins.toJSON (iface.hostBridge or null)}

        available bridgeNameMap keys:
        ${builtins.toJSON (sortedAttrNames bridgeNameMap)}

        attachTargets:
        ${builtins.toJSON localAttachTargets}
      '';

  desiredContainerBaseNameForUnit =
    unitName:
    let
      containerConfig = containerConfigForUnit unitName;
    in
    if containerConfig ? name && builtins.isString containerConfig.name then
      containerConfig.name
    else
      runtimeTargetIdForUnit unitName;

  desiredContainerBaseNames = builtins.listToAttrs (
    map (unitName: {
      name = unitName;
      value = desiredContainerBaseNameForUnit unitName;
    }) selectedUnits
  );

  desiredContainerBaseCounts = builtins.foldl' (
    acc: unitName:
    let
      baseName = desiredContainerBaseNames.${unitName};
    in
    acc
    // {
      ${baseName} = (acc.${baseName} or 0) + 1;
    }
  ) { } selectedUnits;

  candidateContainerNames = builtins.listToAttrs (
    map (
      unitName:
      let
        baseName = desiredContainerBaseNames.${unitName};
      in
      {
        name = unitName;
        value =
          if desiredContainerBaseCounts.${baseName} == 1 then
            baseName
          else
            "${baseName}-${builtins.substring 0 6 (builtins.hashString "sha256" unitName)}";
      }
    ) selectedUnits
  );

  candidateContainerNameValues = map (unitName: candidateContainerNames.${unitName}) selectedUnits;

  _validateUniqueContainerNames =
    if
      builtins.length (lib.unique candidateContainerNameValues)
      == builtins.length candidateContainerNameValues
    then
      true
    else
      throw ''
        s88/CM/network/mapping/container-runtime.nix: candidate container names are not unique

        candidateContainerNames:
        ${builtins.toJSON candidateContainerNames}
      '';

  containerNameForUnit =
    unitName: builtins.seq _validateUniqueContainerNames candidateContainerNames.${unitName};

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
          attachTarget = attachTargetForInterface {
            inherit unitName ifName iface;
          };
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
          };
        }
      ) (sortedAttrNames interfaces);

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
      ) (sortedAttrNames interfaces)
    );

  mkContainerRuntime =
    unitName:
    let
      runtimeTarget = runtimeTargetForUnit unitName;

      unitRuntimeTargetId = runtimeTargetIdForUnit unitName;

      containerName = containerNameForUnit unitName;

      interfaces = normalizedInterfacesForUnit {
        inherit unitName containerName;
        interfaces = runtimeTarget.interfaces or { };
      };

      roleName = roleForUnit unitName;
      roleConfig = roleConfigForUnit unitName;
      containerConfig = containerConfigForUnit unitName;

      profilePath = if containerConfig ? profilePath then containerConfig.profilePath else null;

      additionalCapabilities =
        if
          containerConfig ? additionalCapabilities && builtins.isList containerConfig.additionalCapabilities
        then
          containerConfig.additionalCapabilities
        else
          [ ];

      bindMounts =
        if containerConfig ? bindMounts && builtins.isAttrs containerConfig.bindMounts then
          containerConfig.bindMounts
        else
          { };

      allowedDevices =
        if containerConfig ? allowedDevices && builtins.isList containerConfig.allowedDevices then
          containerConfig.allowedDevices
        else
          [ ];

      interfaceNames = sortedAttrNames interfaces;

      interfaceNameFor =
        ifName:
        let
          iface = interfaces.${ifName};
        in
        if iface ? containerInterfaceName && builtins.isString iface.containerInterfaceName then
          iface.containerInterfaceName
        else if iface ? hostInterfaceName && builtins.isString iface.hostInterfaceName then
          iface.hostInterfaceName
        else
          ifName;

      wanInterfaceNames = map interfaceNameFor (
        lib.filter (ifName: interfaces.${ifName}.sourceKind == "wan") interfaceNames
      );

      lanInterfaceNames = map interfaceNameFor (
        lib.filter (ifName: interfaces.${ifName}.sourceKind != "wan") interfaceNames
      );
    in
    {
      inherit
        deploymentHostName
        hostContext
        runtimeTarget
        roleName
        roleConfig
        profilePath
        bindMounts
        allowedDevices
        additionalCapabilities
        wanInterfaceNames
        lanInterfaceNames
        interfaces
        ;
      unitKey = unitName;
      unitName = unitRuntimeTargetId;
      inherit containerName;
      loopback = runtimeTarget.loopback or { };
      veths = vethsForInterfaces interfaces;
    };
in
builtins.listToAttrs (
  map (unitName: {
    name = unitName;
    value = mkContainerRuntime unitName;
  }) (lib.filter containerEnabledForUnit selectedUnits)
)
