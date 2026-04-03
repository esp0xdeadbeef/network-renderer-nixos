{
  lib,
  hostPlan ? null,
  cpm ? null,
  inventory ? { },
  debugEnabled ? false,
  containerModelsByHost ? null,
  containerModels ? null,
  deploymentContainers ? null,
  models ? null,
  ...
}:

let
  defaultDeploymentHostName =
    if hostPlan != null && builtins.isAttrs hostPlan && hostPlan ? deploymentHostName then
      hostPlan.deploymentHostName
    else if hostPlan != null && builtins.isAttrs hostPlan && hostPlan ? hostName then
      hostPlan.hostName
    else
      null;

  flatModels =
    if hostPlan != null then
      import ../mapping/container-runtime.nix {
        inherit lib hostPlan;
      }
    else
      null;

  modelsByHost =
    if containerModelsByHost != null then
      containerModelsByHost
    else if containerModels != null then
      containerModels
    else if deploymentContainers != null then
      deploymentContainers
    else if models != null then
      models
    else
      null;

  tenantBridgeOverrideForInterface =
    iface:
    let
      renderedHostBridgeName =
        if iface ? renderedHostBridgeName && builtins.isString iface.renderedHostBridgeName then
          iface.renderedHostBridgeName
        else
          "";
    in
    if
      (iface ? sourceKind && iface.sourceKind == "tenant")
      && (iface ? backingRef && builtins.isAttrs iface.backingRef)
      && (iface.backingRef ? kind && iface.backingRef.kind == "attachment")
      && (
        iface.backingRef ? name && builtins.isString iface.backingRef.name && iface.backingRef.name != ""
      )
      && lib.hasPrefix "rt--tena-" renderedHostBridgeName
    then
      iface.backingRef.name
    else
      null;

  tenantBridgeOverrides =
    model:
    lib.foldl' (
      acc: iface:
      let
        override = tenantBridgeOverrideForInterface iface;

        vethName =
          if iface ? hostVethName && builtins.isString iface.hostVethName && iface.hostVethName != "" then
            iface.hostVethName
          else if
            iface ? containerInterfaceName
            && builtins.isString iface.containerInterfaceName
            && iface.containerInterfaceName != ""
          then
            iface.containerInterfaceName
          else
            null;
      in
      if override != null && vethName != null then acc // { ${vethName} = override; } else acc
    ) { } (builtins.attrValues (model.interfaces or { }));

  applyTenantBridgeOverrides =
    model:
    let
      overrides = tenantBridgeOverrides model;

      renderedVeths = lib.mapAttrs (
        vethName: veth:
        if builtins.hasAttr vethName overrides then
          veth // { hostBridge = overrides.${vethName}; }
        else
          veth
      ) (model.veths or { });

      renderedInterfaces = lib.mapAttrs (
        _: iface:
        let
          vethName =
            if iface ? hostVethName && builtins.isString iface.hostVethName && iface.hostVethName != "" then
              iface.hostVethName
            else if
              iface ? containerInterfaceName
              && builtins.isString iface.containerInterfaceName
              && iface.containerInterfaceName != ""
            then
              iface.containerInterfaceName
            else
              null;
        in
        if vethName != null && builtins.hasAttr vethName overrides then
          iface // { renderedHostBridgeName = overrides.${vethName}; }
        else
          iface
      ) (model.interfaces or { });
    in
    model
    // {
      veths = renderedVeths;
      interfaces = renderedInterfaces;
    };

  mkContainer =
    deploymentHostName: containerName: model:
    let
      renderedModel = applyTenantBridgeOverrides model;

      renderedFirewall = if renderedModel ? firewall then renderedModel.firewall else { };
    in
    {
      additionalCapabilities = [
        "CAP_NET_ADMIN"
        "CAP_NET_RAW"
      ]
      ++ (
        if
          renderedModel ? additionalCapabilities && builtins.isList renderedModel.additionalCapabilities
        then
          renderedModel.additionalCapabilities
        else
          [ ]
      );

      allowedDevices =
        if renderedModel ? allowedDevices && builtins.isList renderedModel.allowedDevices then
          renderedModel.allowedDevices
        else
          [ ];

      autoStart =
        if renderedModel ? autoStart && builtins.isBool renderedModel.autoStart then
          renderedModel.autoStart
        else
          true;

      bindMounts =
        if renderedModel ? bindMounts && builtins.isAttrs renderedModel.bindMounts then
          renderedModel.bindMounts
        else
          { };

      extraVeths = renderedModel.veths or { };
      privateNetwork = true;

      specialArgs = {
        inherit deploymentHostName;
        s88RoleName = renderedModel.roleName or null;
        unitName =
          if renderedModel ? unitName && builtins.isString renderedModel.unitName then
            renderedModel.unitName
          else
            containerName;
        s88Firewall = renderedFirewall;
      }
      // lib.optionalAttrs debugEnabled {
        s88Debug = renderedModel;
      };
    };

  renderFlatContainers =
    containerModelsFlat:
    builtins.mapAttrs (
      containerName: model:
      mkContainer (
        if model ? deploymentHostName && builtins.isString model.deploymentHostName then
          model.deploymentHostName
        else
          defaultDeploymentHostName
      ) containerName model
    ) containerModelsFlat;

  renderNestedContainers =
    nestedModels:
    lib.mapAttrs (
      deploymentHostName: deploymentHostContainers:
      builtins.mapAttrs (
        containerName: model: mkContainer deploymentHostName containerName model
      ) deploymentHostContainers
    ) nestedModels;
in
if flatModels != null then
  renderFlatContainers flatModels
else if modelsByHost != null then
  renderNestedContainers modelsByHost
else
  { }
