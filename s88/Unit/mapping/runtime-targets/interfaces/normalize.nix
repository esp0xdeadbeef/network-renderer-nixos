{
  lib,
  runtimeContext,
  forwarding,
  common,
  renderedNames,
  hostBridge,
}:

let
  inherit (common) sortedAttrNames stringList normalizeRoutes;
in
rec {
  emittedInterfacesForUnit =
    { cpm, unitName, file ? "s88/Unit/mapping/runtime-targets.nix" }:
    runtimeContext.emittedInterfacesForUnit { inherit cpm unitName file; };

  emittedLoopbackForUnit =
    { cpm, unitName, file ? "s88/Unit/mapping/runtime-targets.nix" }:
    let
      runtimeTarget = runtimeContext.runtimeTargetForUnit { inherit cpm unitName file; };
      effectiveRuntimeRealization =
        if runtimeTarget ? effectiveRuntimeRealization && builtins.isAttrs runtimeTarget.effectiveRuntimeRealization then
          runtimeTarget.effectiveRuntimeRealization
        else
          { };
    in
    effectiveRuntimeRealization.loopback or { };

  normalizedInterfaceForUnit =
    { cpm, unitName, ifName, iface, renderedIfName, file ? "s88/Unit/mapping/runtime-targets.nix" }:
    let
      backingRef =
        if iface ? backingRef && builtins.isAttrs iface.backingRef then
          iface.backingRef
        else
          throw ''
            ${file}: interface '${ifName}' for unit '${unitName}' is missing backingRef

            interface:
            ${builtins.toJSON iface}
          '';
      semanticInterface = forwarding.semanticInterfaceForUnit { inherit cpm unitName ifName iface file; };
      sourceKind =
        if semanticInterface ? kind && builtins.isString semanticInterface.kind then
          semanticInterface.kind
        else if iface ? sourceKind && builtins.isString iface.sourceKind then
          iface.sourceKind
        else if backingRef ? kind && builtins.isString backingRef.kind then
          backingRef.kind
        else
          throw ''
            ${file}: interface '${ifName}' for unit '${unitName}' is missing sourceKind

            interface:
            ${builtins.toJSON iface}
          '';
      connectivity = {
        inherit sourceKind backingRef;
        upstream =
          if iface ? upstream && iface.upstream != null then
            iface.upstream
          else if semanticInterface ? upstream && semanticInterface.upstream != null then
            semanticInterface.upstream
          else
            null;
      };
    in
    iface
    // {
      inherit renderedIfName connectivity sourceKind backingRef semanticInterface;
      addresses = (stringList (iface.addr4 or null)) ++ (stringList (iface.addr6 or null));
      routes = normalizeRoutes (iface.routes or { });
      hostBridge = hostBridge.hostBridgeIdentityForInterface { inherit unitName ifName iface file; };
      semantic = semanticInterface;
    };

  normalizedInterfacesForUnit =
    { cpm, unitName, file ? "s88/Unit/mapping/runtime-targets.nix" }:
    let
      interfaces = emittedInterfacesForUnit { inherit cpm unitName file; };
      renderedInterfaceNameMap = renderedNames.renderedInterfaceNamesForUnit { inherit cpm unitName file; };
    in
    builtins.listToAttrs (
      map (ifName: {
        name = ifName;
        value = normalizedInterfaceForUnit {
          inherit cpm unitName ifName file;
          iface = interfaces.${ifName};
          renderedIfName = renderedInterfaceNameMap.${ifName};
        };
      }) (sortedAttrNames interfaces)
    );
}
