{
  lib,
  hostName,
  platformBinding ? null,
  renderedNetdevs ? { },
}:

let
  isAttrs = builtins.isAttrs;
  isNonEmptyString = value: builtins.isString value && value != "";

  deployment =
    if
      platformBinding != null && isAttrs platformBinding && isAttrs (platformBinding.categories or null)
    then
      (platformBinding.categories.deployment or { })
    else
      { };

  containerTargets =
    if isAttrs (deployment.containerTargets or null) then deployment.containerTargets else { };

  target = containerTargets.${hostName} or null;
  targetPresent = isAttrs target;
  bindings = if targetPresent && isAttrs (target.containers or null) then target.containers else { };

  hostInterfaceBridges =
    if targetPresent && isAttrs (target.interfaceBridges or null) then target.interfaceBridges else { };
  hostDefaultBridge =
    if targetPresent && isNonEmptyString (target.defaultHostBridge or null) then
      target.defaultHostBridge
    else
      null;

  renderedBridges =
    let
      isBridge =
        value:
        isAttrs value
        && (
          ((value.netdevConfig or { }).Kind or null) == "bridge"
          || (value.kind or null) == "bridge"
          || (value.Kind or null) == "bridge"
        );
    in
    builtins.filter (name: isBridge renderedNetdevs.${name}) (builtins.attrNames renderedNetdevs);

  bridgeBinding =
    binding:
    if isNonEmptyString binding then
      binding
    else if isAttrs binding && isNonEmptyString (binding.bridge or null) then
      binding.bridge
    else
      null;

  containerBinding = name: if isAttrs (bindings.${name} or null) then bindings.${name} else { };

  primaryBridge = name: bridgeBinding ((containerBinding name).hostBridge or null);

  interfaceBindings =
    name: container:
    let
      c = containerBinding name;
      ifs = if isAttrs (c.interfaces or null) then c.interfaces else { };
      perContainer = builtins.mapAttrs (_: bridgeBinding) ifs;

      vethKeys = builtins.attrNames (
        if isAttrs (container.extraVeths or null) then container.extraVeths else { }
      );
      components = key: lib.splitString "-" key;
      matches = ifName: key: builtins.elem ifName (components key);
      modelInterfaces =
        builtins.attrNames ifs
        ++ builtins.concatMap (ifName: builtins.filter (key: matches ifName key) vethKeys) (
          builtins.filter (ifName: builtins.any (key: matches ifName key) vethKeys) (
            builtins.attrNames hostInterfaceBridges
          )
        );

      vethBindings = builtins.listToAttrs (
        builtins.concatMap (
          ifName:
          let
            bridge = bridgeBinding (hostInterfaceBridges.${ifName} or hostDefaultBridge);
          in
          map (key: {
            name = key;
            value = bridge;
          }) (builtins.filter (key: matches ifName key) vethKeys)
        ) (builtins.attrNames hostInterfaceBridges)
      );
    in
    perContainer // vethBindings;

  requestedBridges =
    name:
    let
      primary = primaryBridge name;

      perInterface =
        builtins.mapAttrs (_: bridgeBinding) (
          if isAttrs ((containerBinding name).interfaces or null) then
            (containerBinding name).interfaces
          else
            { }
        )
        // builtins.mapAttrs (_: b: bridgeBinding b) hostInterfaceBridges;
    in
    lib.unique (
      lib.optional (primary != null) primary
      ++ builtins.filter (b: b != null) (builtins.attrValues perInterface)
    );

  missingBridges =
    name: builtins.filter (b: !(builtins.elem b renderedBridges)) (requestedBridges name);

  unboundInterfaces =
    name:
    let
      c = containerBinding name;
      ifs = if isAttrs (c.interfaces or null) then c.interfaces else { };
    in
    builtins.filter (ifName: bridgeBinding ifs.${ifName} == null) (builtins.attrNames ifs);

  diagnosticsFor =
    name:
    let
      missing = missingBridges name;
      unbound = unboundInterfaces name;
    in
    lib.optional (targetPresent && builtins.length missing > 0) (
      "FS-770-HDS-010-SDS-010-SMS-010: CONTAINER_HOST_BRIDGE_MISSING [platform-binding]: "
      + "container '${name}' on host '${hostName}' is bound to host bridge(s) "
      + lib.concatStringsSep ", " (map (b: "'${b}'") missing)
      + " that this host does not render; the container must not start unattached"
    )
    ++ lib.optional (builtins.length unbound > 0) (
      "FS-770-HDS-010-SDS-010-SMS-010: CONTAINER_INTERFACE_UNBOUND [platform-binding]: "
      + "container '${name}' on host '${hostName}' declares interface(s) "
      + lib.concatStringsSep ", " (map (i: "'${i}'") unbound)
      + " with no host bridge in the binding"
    );

  apply =
    name: container:
    let
      primary = primaryBridge name;
      perInterface = interfaceBindings name container;
      existingVeths = if isAttrs (container.extraVeths or null) then container.extraVeths else { };
      vethFor =
        ifName: bridge:
        let
          existing = if isAttrs (existingVeths.${ifName} or null) then existingVeths.${ifName} else { };
        in
        existing
        // {
          hostBridge = if isNonEmptyString (existing.hostBridge or null) then existing.hostBridge else bridge;
        };
      boundVeths = builtins.mapAttrs vethFor (builtins.removeAttrs perInterface [ "" ]);
    in
    container
    // lib.optionalAttrs (primary != null && !(isNonEmptyString (container.hostBridge or null))) {
      hostBridge = primary;
    }
    // lib.optionalAttrs (boundVeths != { }) {
      extraVeths = existingVeths // boundVeths;
    };

  diagnostics = containers: lib.concatMap diagnosticsFor (builtins.attrNames containers);

  applyAll =
    containers:
    let
      problems = diagnostics containers;
    in
    if problems == [ ] then
      builtins.mapAttrs apply containers
    else
      throw (lib.concatStringsSep "\n" problems);
in
{
  inherit
    apply
    applyAll
    diagnostics
    renderedBridges
    bindings
    targetPresent
    ;
}
