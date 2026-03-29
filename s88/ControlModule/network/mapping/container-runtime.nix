{
  lib,
  hostPlan,
}:

let
  hostNaming = import ../../../../lib/host-naming.nix { inherit lib; };

  sortedAttrNames = attrs: lib.sort builtins.lessThan (builtins.attrNames attrs);

  normalizedRuntimeTargets = hostPlan.normalizedRuntimeTargets or { };
  selectedUnits = hostPlan.selectedUnits or [ ];
  selectedRoles = hostPlan.selectedRoles or { };
  unitRoles = hostPlan.unitRoles or { };
  localAttachTargets = hostPlan.localAttachTargets or [ ];
  bridgeNameMap = hostPlan.bridgeNameMap or { };
  deploymentHostName = hostPlan.deploymentHostName or null;
  hostContext = hostPlan.resolvedHostContext or { };

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

  normalizedInterfacesForUnit =
    {
      unitName,
      interfaces,
    }:
    builtins.listToAttrs (
      map (
        ifName:
        let
          iface = interfaces.${ifName};
          renderedIfName = iface.renderedIfName or ifName;
          attachTarget = attachTargetForInterface {
            inherit unitName ifName iface;
          };
          sourceKind = sourceKindForInterface iface;
        in
        {
          name = ifName;
          value = {
            inherit
              ifName
              renderedIfName
              sourceKind
              ;
            addresses = iface.addresses or [ ];
            routes = iface.routes or [ ];
            renderedHostBridgeName = attachTarget.renderedHostBridgeName;
            assignedUplinkName = attachTarget.assignedUplinkName or null;
            hostInterfaceName = hostNaming.shorten "${unitName}-${renderedIfName}";
          };
        }
      ) (sortedAttrNames interfaces)
    );

  vethsForInterfaces =
    interfaces:
    builtins.listToAttrs (
      map (
        ifName:
        let
          iface = interfaces.${ifName};
        in
        {
          name = iface.hostInterfaceName;
          value = {
            hostBridge = iface.renderedHostBridgeName;
          };
        }
      ) (sortedAttrNames interfaces)
    );

  mkContainerRuntime =
    unitName:
    let
      runtimeTarget =
        if builtins.hasAttr unitName normalizedRuntimeTargets then
          normalizedRuntimeTargets.${unitName}
        else
          throw ''
            s88/CM/network/mapping/container-runtime.nix: missing normalized runtime target for unit '${unitName}'
          '';

      interfaces = normalizedInterfacesForUnit {
        inherit unitName;
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

      wanInterfaceNames = map (ifName: interfaces.${ifName}.hostInterfaceName) (
        lib.filter (ifName: interfaces.${ifName}.sourceKind == "wan") interfaceNames
      );

      lanInterfaceNames = map (ifName: interfaces.${ifName}.hostInterfaceName) (
        lib.filter (ifName: interfaces.${ifName}.sourceKind != "wan") interfaceNames
      );
    in
    {
      inherit
        unitName
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
