{
  lib,
  model,
}:

let
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
    renderedModel:
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
    ) { } (builtins.attrValues (renderedModel.interfaces or { }));

  applyTenantBridgeOverrides =
    renderedModel:
    let
      overrides = tenantBridgeOverrides renderedModel;

      renderedVeths = lib.mapAttrs (
        vethName: veth:
        if builtins.hasAttr vethName overrides then
          veth
          // {
            hostBridge = overrides.${vethName};
          }
        else
          veth
      ) (renderedModel.veths or { });

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
      ) (renderedModel.interfaces or { });
    in
    renderedModel
    // {
      veths = renderedVeths;
      interfaces = renderedInterfaces;
    };
in
applyTenantBridgeOverrides model
