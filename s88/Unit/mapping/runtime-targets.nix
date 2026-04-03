{ lib }:

let
  runtimeContext = import ../lookup/runtime-context.nix { inherit lib; };
  hostNaming = import ../../../lib/host-naming.nix { inherit lib; };

  sortedAttrNames = attrs: lib.sort builtins.lessThan (builtins.attrNames attrs);

  stringList =
    value:
    if value == null then
      [ ]
    else if builtins.isString value then
      [ value ]
    else if builtins.isList value then
      lib.filter builtins.isString value
    else
      [ ];

  routeList =
    value:
    if value == null then
      [ ]
    else if builtins.isList value then
      value
    else
      [ value ];

  normalizeRoutes =
    routes:
    let
      routeTree = if builtins.isAttrs routes then routes else { };
    in
    (routeList (routeTree.ipv4 or [ ])) ++ (routeList (routeTree.ipv6 or [ ]));

  identityPartToString =
    value:
    if value == null then
      null
    else if builtins.isString value then
      value
    else if builtins.isInt value || builtins.isFloat value || builtins.isBool value then
      builtins.toJSON value
    else if builtins.isList value || builtins.isAttrs value then
      builtins.toJSON value
    else
      builtins.toString value;

  attrPathOrNull =
    attrs: path:
    if path == [ ] then
      attrs
    else if !builtins.isAttrs attrs then
      null
    else
      let
        key = builtins.head path;
        rest = builtins.tail path;
      in
      if builtins.hasAttr key attrs then attrPathOrNull attrs.${key} rest else null;

  lastStringSegment =
    separator: value:
    let
      parts = lib.splitString separator value;
      count = builtins.length parts;
    in
    if count == 0 then null else builtins.elemAt parts (count - 1);

  forwardingModelFromCpm =
    cpm:
    if cpm ? forwardingModel && builtins.isAttrs cpm.forwardingModel then
      cpm.forwardingModel
    else if
      cpm ? control_plane_model
      && builtins.isAttrs cpm.control_plane_model
      && cpm.control_plane_model ? forwardingModel
      && builtins.isAttrs cpm.control_plane_model.forwardingModel
    then
      cpm.control_plane_model.forwardingModel
    else
      { };

  forwardingSiteForUnit =
    {
      cpm,
      unitName,
      file ? "s88/Unit/mapping/runtime-targets.nix",
    }:
    let
      runtimeTarget = runtimeContext.runtimeTargetForUnit {
        inherit cpm unitName file;
      };

      logicalNode =
        if runtimeTarget ? logicalNode && builtins.isAttrs runtimeTarget.logicalNode then
          runtimeTarget.logicalNode
        else
          { };

      enterprise =
        if logicalNode ? enterprise && builtins.isString logicalNode.enterprise then
          logicalNode.enterprise
        else
          null;

      site = if logicalNode ? site && builtins.isString logicalNode.site then logicalNode.site else null;

      candidate =
        if enterprise != null && site != null then
          attrPathOrNull (forwardingModelFromCpm cpm) [
            "enterprise"
            enterprise
            "site"
            site
          ]
        else
          null;
    in
    if builtins.isAttrs candidate then candidate else { };

  forwardingNodeInterfacesForUnit =
    {
      cpm,
      unitName,
      file ? "s88/Unit/mapping/runtime-targets.nix",
    }:
    let
      runtimeTarget = runtimeContext.runtimeTargetForUnit {
        inherit cpm unitName file;
      };

      logicalNode =
        if runtimeTarget ? logicalNode && builtins.isAttrs runtimeTarget.logicalNode then
          runtimeTarget.logicalNode
        else
          { };

      nodeName =
        if logicalNode ? name && builtins.isString logicalNode.name then logicalNode.name else unitName;

      site = forwardingSiteForUnit {
        inherit cpm unitName file;
      };

      nodes = if site ? nodes && builtins.isAttrs site.nodes then site.nodes else { };

      node =
        if builtins.hasAttr nodeName nodes && builtins.isAttrs nodes.${nodeName} then
          nodes.${nodeName}
        else
          { };
    in
    if node ? interfaces && builtins.isAttrs node.interfaces then node.interfaces else { };

  semanticInterfaceForUnit =
    {
      cpm,
      unitName,
      ifName,
      iface,
      file ? "s88/Unit/mapping/runtime-targets.nix",
    }:
    let
      nodeInterfaces = forwardingNodeInterfacesForUnit {
        inherit cpm unitName file;
      };

      backingRef =
        if iface ? backingRef && builtins.isAttrs iface.backingRef then iface.backingRef else { };

      backingRefIdTail =
        if backingRef ? id && builtins.isString backingRef.id then
          lastStringSegment "::" backingRef.id
        else
          null;

      candidateKeys = lib.unique (
        lib.filter builtins.isString [
          ifName
          (iface.sourceInterface or null)
          (if backingRef ? name && builtins.isString backingRef.name then backingRef.name else null)
          backingRefIdTail
        ]
      );

      matchedKeys = lib.filter (candidateKey: builtins.hasAttr candidateKey nodeInterfaces) candidateKeys;
    in
    if matchedKeys == [ ] then
      { }
    else if builtins.length matchedKeys == 1 then
      nodeInterfaces.${builtins.head matchedKeys}
    else
      throw ''
        ${file}: multiple semantic forwarding interfaces matched runtime interface '${ifName}' for unit '${unitName}'

        matched keys:
        ${builtins.toJSON matchedKeys}
      '';

  emittedInterfacesForUnit =
    {
      cpm,
      unitName,
      file ? "s88/Unit/mapping/runtime-targets.nix",
    }:
    runtimeContext.emittedInterfacesForUnit {
      inherit cpm unitName file;
    };

  emittedLoopbackForUnit =
    {
      cpm,
      unitName,
      file ? "s88/Unit/mapping/runtime-targets.nix",
    }:
    let
      runtimeTarget = runtimeContext.runtimeTargetForUnit {
        inherit cpm unitName file;
      };

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

  desiredRenderedIfNameForInterface =
    {
      ifName,
      iface,
    }:
    if iface ? renderedIfName && builtins.isString iface.renderedIfName then
      iface.renderedIfName
    else
      ifName;

  renderedInterfaceNamesForUnit =
    {
      cpm,
      unitName,
      file ? "s88/Unit/mapping/runtime-targets.nix",
    }:
    let
      interfaces = emittedInterfacesForUnit {
        inherit cpm unitName file;
      };

      interfaceNames = sortedAttrNames interfaces;

      desiredRenderedIfNameMap = builtins.listToAttrs (
        map (ifName: {
          name = ifName;
          value = desiredRenderedIfNameForInterface {
            inherit ifName;
            iface = interfaces.${ifName};
          };
        }) interfaceNames
      );

      desiredRenderedIfNames = map (ifName: desiredRenderedIfNameMap.${ifName}) interfaceNames;

      uniqueDesiredRenderedIfNames = lib.unique desiredRenderedIfNames;

      _validateDesiredRenderedIfNames =
        if builtins.length uniqueDesiredRenderedIfNames == builtins.length desiredRenderedIfNames then
          true
        else
          throw ''
            ${file}: duplicate desired rendered interface names for unit '${unitName}'

            desiredRenderedIfNameMap:
            ${builtins.toJSON desiredRenderedIfNameMap}
          '';

      renderedNameMap = hostNaming.ensureUnique uniqueDesiredRenderedIfNames;
    in
    builtins.seq _validateDesiredRenderedIfNames (
      builtins.listToAttrs (
        map (ifName: {
          name = ifName;
          value = renderedNameMap.${desiredRenderedIfNameMap.${ifName}};
        }) interfaceNames
      )
    );

  hostBridgeIdentityForInterface =
    {
      unitName,
      ifName,
      iface,
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

      backingRefId =
        if backingRef ? id && builtins.isString backingRef.id then
          backingRef.id
        else
          throw ''
            ${file}: interface '${ifName}' for unit '${unitName}' is missing backingRef.id

            interface:
            ${builtins.toJSON iface}
          '';

      backingRefKind =
        if backingRef ? kind && builtins.isString backingRef.kind then
          backingRef.kind
        else
          throw ''
            ${file}: interface '${ifName}' for unit '${unitName}' is missing backingRef.kind

            interface:
            ${builtins.toJSON iface}
          '';

      sourceKind =
        if iface ? sourceKind && builtins.isString iface.sourceKind then
          iface.sourceKind
        else
          backingRefKind;

      upstream = identityPartToString (iface.upstream or null);

      segments = lib.filter builtins.isString (
        [
          "rt"
          sourceKind
          backingRefKind
          backingRefId
        ]
        ++ lib.optionals (upstream != null) [ upstream ]
      );
    in
    builtins.concatStringsSep "--" segments;

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

      semanticInterface = semanticInterfaceForUnit {
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

      addresses = (stringList (iface.addr4 or null)) ++ (stringList (iface.addr6 or null));

      routes = normalizeRoutes (iface.routes or { });

      hostBridge = hostBridgeIdentityForInterface {
        inherit
          unitName
          ifName
          iface
          file
          ;
      };

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
      inherit
        renderedIfName
        addresses
        routes
        hostBridge
        connectivity
        sourceKind
        backingRef
        semanticInterface
        ;
      semantic = semanticInterface;
    };

  normalizedInterfacesForUnit =
    {
      cpm,
      unitName,
      file ? "s88/Unit/mapping/runtime-targets.nix",
    }:
    let
      interfaces = emittedInterfacesForUnit {
        inherit cpm unitName file;
      };

      renderedInterfaceNameMap = renderedInterfaceNamesForUnit {
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

  normalizedRuntimeTargetForUnit =
    {
      cpm,
      unitName,
      file ? "s88/Unit/mapping/runtime-targets.nix",
    }:
    let
      runtimeTarget = runtimeContext.runtimeTargetForUnit {
        inherit cpm unitName file;
      };
    in
    runtimeTarget
    // {
      interfaces = normalizedInterfacesForUnit {
        inherit cpm unitName file;
      };
      loopback = emittedLoopbackForUnit {
        inherit cpm unitName file;
      };
    };

  normalizedRuntimeTargets =
    {
      cpm,
      file ? "s88/Unit/mapping/runtime-targets.nix",
    }:
    let
      targets = runtimeContext.runtimeTargets cpm;
    in
    builtins.listToAttrs (
      map (unitName: {
        name = unitName;
        value = normalizedRuntimeTargetForUnit {
          inherit cpm unitName file;
        };
      }) (sortedAttrNames targets)
    );
in
{
  inherit
    emittedInterfacesForUnit
    emittedLoopbackForUnit
    desiredRenderedIfNameForInterface
    renderedInterfaceNamesForUnit
    hostBridgeIdentityForInterface
    normalizedInterfaceForUnit
    normalizedInterfacesForUnit
    normalizedRuntimeTargetForUnit
    normalizedRuntimeTargets
    ;
}
