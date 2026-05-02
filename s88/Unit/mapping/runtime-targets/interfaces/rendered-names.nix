{ lib, runtimeContext, common }:

let
  inherit (common) sortedAttrNames;
  maxInterfaceNameLength = 15;

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
        prefix = if prefixLen > 0 then builtins.substring 0 prefixLen baseName else builtins.substring 0 1 baseName;
      in
      "${prefix}${suffix}";

  resolveUniqueInterfaceName =
    { baseName, usedNames, index ? 1 }:
    let candidate = uniqueInterfaceNameCandidate baseName index;
    in
    if !(builtins.hasAttr candidate usedNames) then
      candidate
    else
      resolveUniqueInterfaceName { inherit baseName usedNames; index = index + 1; };

  ensureUniqueRenderedNames =
    names:
    (builtins.foldl'
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
          usedNames = acc.usedNames // { ${renderedName} = true; };
          renderedNameMap = acc.renderedNameMap // { ${originalName} = renderedName; };
        }
      )
      { usedNames = { }; renderedNameMap = { }; }
      names).renderedNameMap;
in
{
  desiredRenderedIfNameForInterface =
    { ifName, iface }:
    if iface ? renderedIfName && builtins.isString iface.renderedIfName then iface.renderedIfName else ifName;

  renderedInterfaceNamesForUnit =
    { cpm, unitName, file ? "s88/Unit/mapping/runtime-targets.nix" }:
    let
      interfaces = runtimeContext.emittedInterfacesForUnit { inherit cpm unitName file; };
      interfaceNames = sortedAttrNames interfaces;
      desiredRenderedIfNameMap = builtins.listToAttrs (
        map (ifName: {
          name = ifName;
          value = if interfaces.${ifName} ? renderedIfName && builtins.isString interfaces.${ifName}.renderedIfName then interfaces.${ifName}.renderedIfName else ifName;
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
}
