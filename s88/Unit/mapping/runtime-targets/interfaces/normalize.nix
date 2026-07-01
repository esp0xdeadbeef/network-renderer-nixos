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

  attrsOrEmpty = value: if builtins.isAttrs value then value else { };

  nixosMaterializationFor =
    iface:
    let
      direct = attrsOrEmpty (iface.materialization or null);
      connectivity = attrsOrEmpty (iface.connectivity or null);
      connectivityMaterialization = attrsOrEmpty (connectivity.materialization or null);
    in
    attrsOrEmpty (direct.nixos or connectivityMaterialization.nixos or null);

  nixosOwnsInterface =
    iface:
    let
      materialization = nixosMaterializationFor iface;
    in
    (materialization.ownsInterface or false) == true
    || (materialization.owner or null) == "network-renderer-nixos";

  isProviderOwnedOverlayInterface =
    iface:
    let
      backingRef = attrsOrEmpty (iface.backingRef or null);
      connectivity = attrsOrEmpty (iface.connectivity or null);
      connectivityBackingRef = attrsOrEmpty (connectivity.backingRef or null);
    in
    (iface.sourceKind or null) == "overlay"
    || (connectivity.sourceKind or null) == "overlay"
    || (backingRef.kind or null) == "overlay"
    || (connectivityBackingRef.kind or null) == "overlay";

  shouldEmitInterface = iface: !(isProviderOwnedOverlayInterface iface) || nixosOwnsInterface iface;
in
rec {
  emittedInterfacesForUnit =
    {
      cpm,
      unitName,
      file ? "s88/Unit/mapping/runtime-targets.nix",
    }:
    runtimeContext.emittedInterfacesForUnit { inherit cpm unitName file; };

  emittedLoopbackForUnit =
    {
      cpm,
      unitName,
      file ? "s88/Unit/mapping/runtime-targets.nix",
    }:
    let
      runtimeTarget = runtimeContext.runtimeTargetForUnit { inherit cpm unitName file; };
      effectiveRuntimeRealization =
        if
          runtimeTarget ? effectiveRuntimeRealization
          && builtins.isAttrs runtimeTarget.effectiveRuntimeRealization
        then
          runtimeTarget.effectiveRuntimeRealization
        else
          { };
    in
    effectiveRuntimeRealization.loopback or { };

  normalizedInterfaceForUnit =
    {
      cpm,
      unitName,
      ifName,
      iface,
      renderedIfName,
      file ? "s88/Unit/mapping/runtime-targets.nix",
    }:
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
      semanticInterface = forwarding.semanticInterfaceForUnit {
        inherit
          cpm
          unitName
          ifName
          iface
          file
          ;
      };
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
      interfaceClass =
        if iface ? interfaceClass && builtins.isAttrs iface.interfaceClass && iface.interfaceClass != { } then
          iface.interfaceClass
        else if backingRef ? service && backingRef.service == "pppoe" then
          # PPPoE service interfaces do not carry interfaceClass; their
          # role is determined by the PPPoE session, not interface topology.
          { }
        else
          throw ''
            FS-380-HDS-020-SDS-010-SMS-050: interface '${ifName}' for unit '${unitName}' is missing CPM interfaceClass

            The NixOS renderer must consume explicit CPM interfaceClass data and must not reconstruct interface
            role semantics from sourceKind, backingRef, lane names, role names, or inventory.

            interface:
            ${builtins.toJSON iface}
          '';
    in
    iface
    // {
      inherit
        renderedIfName
        connectivity
        sourceKind
        backingRef
        semanticInterface
        interfaceClass
        ;
      addresses = (stringList (iface.addr4 or null)) ++ (stringList (iface.addr6 or null));
      routes = normalizeRoutes (iface.routes or { });
      hostBridge = hostBridge.hostBridgeIdentityForInterface {
        inherit
          unitName
          ifName
          iface
          file
          ;
      };
      semantic = semanticInterface;
    };

  normalizedInterfacesForUnit =
    {
      cpm,
      unitName,
      file ? "s88/Unit/mapping/runtime-targets.nix",
    }:
    let
      interfacesAll = emittedInterfacesForUnit { inherit cpm unitName file; };
      interfaces = lib.filterAttrs (_ifName: iface: shouldEmitInterface iface) interfacesAll;
      renderedInterfaceNameMap = renderedNames.renderedInterfaceNamesForUnit {
        inherit cpm unitName file;
      };
    in
    builtins.listToAttrs (
      map (ifName: {
        name = ifName;
        value = normalizedInterfaceForUnit {
          inherit
            cpm
            unitName
            ifName
            file
            ;
          iface = interfaces.${ifName};
          renderedIfName = renderedInterfaceNameMap.${ifName};
        };
      }) (sortedAttrNames interfaces)
    );
}
