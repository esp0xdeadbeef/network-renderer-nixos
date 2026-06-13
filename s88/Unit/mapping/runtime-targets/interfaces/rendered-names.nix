{ lib, runtimeContext, common }:

let
  inherit (common) sortedAttrNames;
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
        map
          (ifName: {
            name = ifName;
            value = if interfaces.${ifName} ? renderedIfName && builtins.isString interfaces.${ifName}.renderedIfName then interfaces.${ifName}.renderedIfName else ifName;
          })
          interfaceNames
      );
      desiredRenderedIfNames = map (ifName: desiredRenderedIfNameMap.${ifName}) interfaceNames;
      uniqueDesiredRenderedIfNames = lib.unique desiredRenderedIfNames;
      hasDuplicates = builtins.length uniqueDesiredRenderedIfNames != builtins.length desiredRenderedIfNames;
      _rejectDuplicates =
        if !hasDuplicates then
          true
        else
          let
            countOccurrences = name:
              builtins.length (builtins.filter (n: n == name) desiredRenderedIfNames);
            nameCounts = map (name: { inherit name; count = countOccurrences name; }) uniqueDesiredRenderedIfNames;
            duplicates = builtins.filter (nc: nc.count > 1) nameCounts;
            duplicateName = if duplicates == [ ] then null else (builtins.head duplicates).name;
            collidingIfNames = builtins.filter
              (ifName: desiredRenderedIfNameMap.${ifName} == duplicateName)
              interfaceNames;
          in
          throw ''
            diagnostic.duplicate-rendered-interface-name:
              unit: ${unitName}
              collidingInterface: ${duplicateName}
              collidingNames: ${builtins.toJSON collidingIfNames}
              owningLayer: NFM/CPM
              reason: Two or more desired interface names within unit '${unitName}' map to the same rendered interface name '${duplicateName}'. The owning layer (NFM/CPM or inventory) must resolve this collision before the renderer can proceed.
          '';
    in
    builtins.seq _rejectDuplicates (
      builtins.listToAttrs (
        map
          (ifName: {
            name = ifName;
            value = desiredRenderedIfNameMap.${ifName};
          })
          interfaceNames
      )
    );
}
