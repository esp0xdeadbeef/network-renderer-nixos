{ lib }:

let
  interfaceNaming = import ../mapping/container-runtime/interfaces/naming.nix { inherit lib; };

  attrsOrEmpty = value: if builtins.isAttrs value then value else { };
  inherit (interfaceNaming)
    validInterfaceName
    semanticBaseInterfaceName
    assignUniqueContainerInterfaceNames
    ;

  isProviderOwnedOverlayInterface =
    iface:
    let
      backingRef = attrsOrEmpty (iface.backingRef or null);
      connectivity = attrsOrEmpty (iface.connectivity or null);
      connectivityBackingRef = attrsOrEmpty (connectivity.backingRef or null);
      materialization = attrsOrEmpty ((attrsOrEmpty (iface.materialization or null)).nixos or null);
    in
    (
      (iface.sourceKind or null) == "overlay"
      || (connectivity.sourceKind or null) == "overlay"
      || (backingRef.kind or null) == "overlay"
      || (connectivityBackingRef.kind or null) == "overlay"
    )
    && (materialization.ownsInterface or false) != true
    && (materialization.owner or null) != "network-renderer-nixos";

  requestedRuntimeIfNameFor =
    ifName: iface:
    if builtins.isString (iface.runtimeIfName or null) && iface.runtimeIfName != "" then
      iface.runtimeIfName
    else if builtins.isString (iface.renderedIfName or null) && iface.renderedIfName != "" then
      iface.renderedIfName
    else
      ifName;

  providerRuntimeInterfaceBaseNameFor =
    ifName: iface:
    let requestedName = requestedRuntimeIfNameFor ifName iface;
    in if validInterfaceName requestedName then requestedName else semanticBaseInterfaceName requestedName;

  providerInterfaceFor =
    decorate: ifName: runtimeIfName: iface:
    let
      backingRef = attrsOrEmpty (iface.backingRef or null);
      requestedRuntimeIfName = requestedRuntimeIfNameFor ifName iface;
      existingAliases =
        if builtins.isList (iface.interfaceAliases or null) then lib.filter builtins.isString iface.interfaceAliases else [ ];
    in
    iface
    // {
      ifName = ifName;
      sourceKind = iface.sourceKind or "overlay";
      runtimeIfName = runtimeIfName;
      renderedIfName = runtimeIfName;
      containerInterfaceName = runtimeIfName;
      interfaceAliases = lib.unique (existingAliases ++ [ ifName requestedRuntimeIfName runtimeIfName ]);
      backingRef = backingRef;
      connectivity = (attrsOrEmpty (iface.connectivity or null)) // {
        sourceKind = iface.sourceKind or "overlay";
        backingRef = backingRef;
      };
      providerCreated = true;
    }
    // decorate {
      inherit ifName runtimeIfName iface backingRef requestedRuntimeIfName;
    };
in
{
  materializeMissingProviderOverlayInterfaces =
    { runtimeInterfaces
    , renderedInterfaces ? { }
    , decorate ? (_: { })
    }:
    let
      providerInterfaceCandidates =
        lib.filterAttrs
          (ifName: iface: !(builtins.hasAttr ifName renderedInterfaces) && isProviderOwnedOverlayInterface iface)
          runtimeInterfaces;
      providerInterfaceEntries =
        assignUniqueContainerInterfaceNames (
          map
            (ifName: {
              inherit ifName;
              value = {
                inherit ifName;
                iface = providerInterfaceCandidates.${ifName};
                containerInterfaceBaseName = providerRuntimeInterfaceBaseNameFor ifName providerInterfaceCandidates.${ifName};
              };
            })
            (lib.sort builtins.lessThan (builtins.attrNames providerInterfaceCandidates))
        );
    in
    builtins.listToAttrs (
      map
        (entry: {
          name = entry.ifName;
          value = providerInterfaceFor decorate entry.ifName entry.value.containerInterfaceName entry.value.iface;
        })
        providerInterfaceEntries
    );
}
