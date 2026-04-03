{
  lib,
  debugEnabled ? false,
  containerModelsByHost ? null,
  containerModels ? null,
  deploymentContainers ? null,
  models ? null,
  ...
}:

let
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
      { };

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
          veth
          // {
            hostBridge = overrides.${vethName};
          }
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
          iface
          // {
            renderedHostBridgeName = overrides.${vethName};
          }
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
    in
    {
      additionalCapabilities = [
        "CAP_NET_ADMIN"
        "CAP_NET_RAW"
      ];
      allowedDevices = [ ];
      autoStart = true;
      bindMounts = { };
      extraVeths = renderedModel.veths or { };
      firewall = renderedModel.firewall or { };
      privateNetwork = true;
      specialArgs = {
        inherit deploymentHostName;
        s88RoleName = renderedModel.roleName;
        unitName = renderedModel.unitName;
      }
      // lib.optionalAttrs debugEnabled {
        s88Debug = renderedModel;
      };
    };
in
lib.mapAttrs (
  deploymentHostName: deploymentHostContainers:
  lib.mapAttrs (
    containerName: model: mkContainer deploymentHostName containerName model
  ) deploymentHostContainers
) modelsByHost
