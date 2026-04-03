{
  lib,
  lookup,
}:

let
  splitQualifiedUnitId =
    unitName:
    let
      parts = lib.splitString "::" unitName;
    in
    {
      inherit parts;
      local = lookup.runtimeTargetIdForUnit unitName;
      qualified = lib.concatStringsSep "-" parts;
    };

  namingUnits = lib.filter lookup.containerEnabledForUnit lookup.deploymentHostContainerNamingUnits;

  parsedNamingUnits = lib.genAttrs namingUnits splitQualifiedUnitId;

  localNameCounts = builtins.foldl' (
    acc: unitName:
    let
      local = parsedNamingUnits.${unitName}.local;
    in
    acc
    // {
      ${local} = (acc.${local} or 0) + 1;
    }
  ) { } namingUnits;

  emittedUnitNameForUnit =
    unitName:
    let
      parsed =
        if builtins.hasAttr unitName parsedNamingUnits then
          parsedNamingUnits.${unitName}
        else
          splitQualifiedUnitId unitName;
    in
    if (localNameCounts.${parsed.local} or 0) > 1 then parsed.qualified else parsed.local;

  desiredContainerBaseNameForUnit =
    unitName:
    let
      containerConfig = lookup.containerConfigForUnit unitName;
    in
    if containerConfig ? name && builtins.isString containerConfig.name then
      containerConfig.name
    else
      emittedUnitNameForUnit unitName;

  desiredContainerBaseNames = builtins.listToAttrs (
    map (unitName: {
      name = unitName;
      value = desiredContainerBaseNameForUnit unitName;
    }) namingUnits
  );

  desiredContainerBaseCounts = builtins.foldl' (
    acc: unitName:
    let
      baseName = desiredContainerBaseNames.${unitName};
    in
    acc
    // {
      ${baseName} = (acc.${baseName} or 0) + 1;
    }
  ) { } namingUnits;

  candidateContainerNames = builtins.listToAttrs (
    map (
      unitName:
      let
        baseName = desiredContainerBaseNames.${unitName};
      in
      {
        name = unitName;
        value =
          if desiredContainerBaseCounts.${baseName} == 1 then
            baseName
          else
            "${baseName}-${builtins.substring 0 6 (builtins.hashString "sha256" unitName)}";
      }
    ) namingUnits
  );

  candidateContainerNameValues = map (unitName: candidateContainerNames.${unitName}) namingUnits;

  validateUniqueContainerNames =
    if
      builtins.length (lib.unique candidateContainerNameValues)
      == builtins.length candidateContainerNameValues
    then
      true
    else
      throw ''
        s88/CM/network/mapping/container-runtime.nix: candidate container names are not unique

        candidateContainerNames:
        ${builtins.toJSON candidateContainerNames}
      '';

  containerNameForUnit =
    unitName:
    if builtins.hasAttr unitName candidateContainerNames then
      builtins.seq validateUniqueContainerNames candidateContainerNames.${unitName}
    else
      throw ''
        s88/CM/network/mapping/container-runtime.nix: missing candidate container name for unit '${unitName}'

        namingUnits:
        ${builtins.toJSON namingUnits}
      '';

  emittedRuntimeUnitNames = map emittedUnitNameForUnit namingUnits;

  validateUniqueEmittedRuntimeUnitNames =
    if
      builtins.length emittedRuntimeUnitNames == builtins.length (lib.unique emittedRuntimeUnitNames)
    then
      true
    else
      throw ''
        s88/CM/network/mapping/container-runtime.nix: emitted runtime unit names are not unique

        namingUnits:
        ${builtins.toJSON namingUnits}

        emittedRuntimeUnitNames:
        ${builtins.toJSON emittedRuntimeUnitNames}
      '';
in
{
  inherit
    namingUnits
    parsedNamingUnits
    emittedUnitNameForUnit
    containerNameForUnit
    validateUniqueContainerNames
    validateUniqueEmittedRuntimeUnitNames
    ;
}
