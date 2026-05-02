{ lib, inventoryModel, common, portResolution }:

let
  inherit (inventoryModel) attachForPort;
  inherit (common) sortedAttrNames runtimeTargetForUnitFromNormalized;

  tryResolvePortForRuntimeInterface =
    args:
    let
      attempt = builtins.tryEval (portResolution.resolvePortForRuntimeInterface args);
    in
    if attempt.success then attempt.value else null;

  attachTargetForRuntimeInterface =
    { inventory, normalizedRuntimeTargets, unitName, ifName, iface, file ? "s88/Unit/physical/realization-ports.nix" }:
    let
      resolvedPort = tryResolvePortForRuntimeInterface { inherit inventory normalizedRuntimeTargets unitName ifName iface file; };
      attachTarget =
        if resolvedPort == null then
          null
        else
          attachForPort {
            inherit file unitName;
            node = resolvedPort.node;
            portName = resolvedPort.portName;
            port = resolvedPort.port;
          };
    in
    if attachTarget == null then
      null
    else
      attachTarget
      // {
        inherit unitName ifName;
        renderedIfName = iface.renderedIfName or null;
        interface = iface;
        connectivity = iface.connectivity or { };
        backingRef = iface.backingRef or { };
        realizationNodeName = resolvedPort.nodeName;
      };

  fallbackAttachTargetForRuntimeInterface =
    { unitName, ifName, iface, file ? "s88/Unit/physical/realization-ports.nix" }:
    let
      hostBridgeName =
        if iface ? hostBridge && builtins.isString iface.hostBridge then
          iface.hostBridge
        else
          throw ''
            ${file}: normalized interface '${ifName}' for unit '${unitName}' is missing hostBridge

            interface:
            ${builtins.toJSON iface}
          '';
    in
    {
      inherit unitName ifName hostBridgeName;
      renderedIfName = iface.renderedIfName or null;
      interface = iface;
      connectivity = iface.connectivity or { };
      backingRef = iface.backingRef or { };
      kind = "synthetic";
      name = hostBridgeName;
      originalName = hostBridgeName;
      identity = {
        unitName = unitName;
        portName = ifName;
        attachmentKind = "synthetic";
      };
    };
in
{
  attachTargetsForUnitsFromRuntime =
    { inventory ? { }, selectedUnits, normalizedRuntimeTargets, file ? "s88/Unit/physical/realization-ports.nix" }:
    lib.concatMap (
      unitName:
      let
        runtimeTarget = runtimeTargetForUnitFromNormalized { inherit normalizedRuntimeTargets unitName file; };
        interfaces =
          if runtimeTarget ? interfaces && builtins.isAttrs runtimeTarget.interfaces then
            runtimeTarget.interfaces
          else
            { };
      in
      map (
        ifName:
        let
          iface = interfaces.${ifName};
          authoritativeTarget =
            if inventory == { } then
              null
            else
              attachTargetForRuntimeInterface { inherit inventory normalizedRuntimeTargets unitName ifName iface file; };
        in
        if authoritativeTarget != null then
          authoritativeTarget
        else
          fallbackAttachTargetForRuntimeInterface { inherit unitName ifName iface file; }
      ) (sortedAttrNames interfaces)
    ) selectedUnits;
}
