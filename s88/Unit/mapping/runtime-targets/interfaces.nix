{ lib }:

let
  runtimeContext = import ../../lookup/runtime-context.nix { inherit lib; };
  forwarding = import ./forwarding.nix { inherit lib; };
  maxInterfaceNameLength = 15;

  sortedAttrNames = attrs: lib.sort builtins.lessThan (builtins.attrNames attrs);

  semanticShortNameForInterface =
    name:
    let
      parts = lib.filter (part: part != "") (lib.splitString "-" name);
      firstPart = if parts != [ ] then builtins.head parts else "";
      lastPart = if parts != [ ] then builtins.elemAt parts (builtins.length parts - 1) else "";
      firstShort = builtins.substring 0 7 firstPart;
      lastShort = builtins.substring 0 7 lastPart;
      joined =
        if firstShort != "" && lastShort != "" && firstShort != lastShort then
          "${firstShort}-${lastShort}"
        else if firstShort != "" then
          firstShort
        else
          builtins.substring 0 maxInterfaceNameLength name;
    in
    if builtins.stringLength name <= maxInterfaceNameLength then
      name
    else if builtins.stringLength joined <= maxInterfaceNameLength && joined != "" then
      joined
    else
      builtins.substring 0 maxInterfaceNameLength name;

  uniqueInterfaceNameCandidate =
    baseName: index:
    if index <= 1 then
      baseName
    else
      let
        suffix = "-${toString index}";
        prefixLen = maxInterfaceNameLength - builtins.stringLength suffix;
        prefix =
          if prefixLen > 0 then builtins.substring 0 prefixLen baseName else builtins.substring 0 1 baseName;
      in
      "${prefix}${suffix}";

  resolveUniqueInterfaceName =
    {
      baseName,
      usedNames,
      index ? 1,
    }:
    let
      candidate = uniqueInterfaceNameCandidate baseName index;
    in
    if !(builtins.hasAttr candidate usedNames) then
      candidate
    else
      resolveUniqueInterfaceName {
        inherit baseName usedNames;
        index = index + 1;
      };

  ensureUniqueRenderedNames =
    names:
    let
      resolved =
        builtins.foldl'
          (
            acc: originalName:
            let
              baseName = semanticShortNameForInterface originalName;
              renderedName = resolveUniqueInterfaceName {
                inherit baseName;
                usedNames = acc.usedNames;
              };
            in
            {
              usedNames = acc.usedNames // {
                ${renderedName} = true;
              };
              renderedNameMap = acc.renderedNameMap // {
                ${originalName} = renderedName;
              };
            }
          )
          {
            usedNames = { };
            renderedNameMap = { };
          }
          names;
    in
    resolved.renderedNameMap;

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
    if builtins.isList routes then
      routeList routes
    else
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

      renderedNameMap = ensureUniqueRenderedNames uniqueDesiredRenderedIfNames;
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

      bridgeBackingRefId =
        if
          sourceKind == "overlay"
          && backingRef ? name
          && builtins.isString backingRef.name
          && backingRef.name != ""
        then
          "overlay::${backingRef.name}"
        else
          backingRefId;

      segments = lib.filter builtins.isString (
        [
          "rt"
          sourceKind
          backingRefKind
          bridgeBackingRefId
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
    ;
}
