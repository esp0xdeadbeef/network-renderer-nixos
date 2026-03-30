{
  lib,
  interfaces ? { },
  wanIfs ? [ ],
  lanIfs ? [ ],
}:

let
  sortedAttrNames = attrs: lib.sort builtins.lessThan (builtins.attrNames attrs);

  asStringList =
    value:
    if value == null then
      [ ]
    else if builtins.isString value then
      [ value ]
    else if builtins.isList value then
      lib.filter builtins.isString value
    else
      [ ];

  interfaceEntries = lib.filter (entry: entry != null) (
    map (
      ifName:
      let
        iface = interfaces.${ifName};

        actualName =
          if
            iface ? containerInterfaceName
            && builtins.isString iface.containerInterfaceName
            && iface.containerInterfaceName != ""
          then
            iface.containerInterfaceName
          else if
            iface ? interfaceName && builtins.isString iface.interfaceName && iface.interfaceName != ""
          then
            iface.interfaceName
          else if
            iface ? hostInterfaceName
            && builtins.isString iface.hostInterfaceName
            && iface.hostInterfaceName != ""
          then
            iface.hostInterfaceName
          else if
            iface ? renderedIfName && builtins.isString iface.renderedIfName && iface.renderedIfName != ""
          then
            iface.renderedIfName
          else if iface ? ifName && builtins.isString iface.ifName && iface.ifName != "" then
            iface.ifName
          else
            null;
      in
      if actualName == null then
        null
      else
        {
          key = ifName;
          name = actualName;
          sourceKind = iface.sourceKind or null;
          assignedUplinkName = iface.assignedUplinkName or null;
          iface = iface;
        }
    ) (sortedAttrNames interfaces)
  );

  interfaceMap = builtins.listToAttrs (
    map (entry: {
      name = entry.name;
      value = entry;
    }) interfaceEntries
  );

  explicitWanNames = lib.filter (name: builtins.hasAttr name interfaceMap) (asStringList wanIfs);

  discoveredWanNames = map (entry: entry.name) (
    lib.filter (entry: (entry.sourceKind or null) == "wan") interfaceEntries
  );

  resolvedWanNames = lib.unique (explicitWanNames ++ discoveredWanNames);

  explicitLanNames = lib.filter (
    name: builtins.hasAttr name interfaceMap && !(builtins.elem name resolvedWanNames)
  ) (asStringList lanIfs);

  discoveredLanNames = map (entry: entry.name) (
    lib.filter (entry: !(builtins.elem entry.name resolvedWanNames)) interfaceEntries
  );

  resolvedLanNames = lib.unique (explicitLanNames ++ discoveredLanNames);
in
{
  inherit
    interfaceEntries
    interfaceMap
    ;

  wanNames = resolvedWanNames;
  lanNames = resolvedLanNames;

  wanEntries = map (name: interfaceMap.${name}) resolvedWanNames;
  lanEntries = map (name: interfaceMap.${name}) resolvedLanNames;
}
