{
  lib,
  interfaceView,
  interfaces,
  wanIfs,
  lanIfs,
  common,
}:

let
  inherit (common) sortedStrings;

  interfaceEntries =
    if interfaceView != null && builtins.isAttrs interfaceView && interfaceView ? interfaceEntries then
      lib.filter builtins.isAttrs interfaceView.interfaceEntries
    else
      [ ];

  interfaceNamesFromRuntime =
    if builtins.isAttrs interfaces then
      map (
        ifName:
        let
          iface = interfaces.${ifName};
        in
        if builtins.isString (iface.containerInterfaceName or null) && iface.containerInterfaceName != "" then
          iface.containerInterfaceName
        else if builtins.isString (iface.interfaceName or null) && iface.interfaceName != "" then
          iface.interfaceName
        else if builtins.isString (iface.hostInterfaceName or null) && iface.hostInterfaceName != "" then
          iface.hostInterfaceName
        else if builtins.isString (iface.renderedIfName or null) && iface.renderedIfName != "" then
          iface.renderedIfName
        else if builtins.isString (iface.ifName or null) && iface.ifName != "" then
          iface.ifName
        else
          null
      ) (lib.sort builtins.lessThan (builtins.attrNames interfaces))
    else
      [ ];

  overlayNames = sortedStrings (
    map (
      entry:
      if
        (
          (entry ? sourceKind && entry.sourceKind == "overlay")
          || (entry ? backingRef && builtins.isAttrs entry.backingRef && (entry.backingRef.kind or null) == "overlay")
          || (entry ? iface && builtins.isAttrs entry.iface && builtins.isAttrs (entry.iface.backingRef or null) && (entry.iface.backingRef.kind or null) == "overlay")
        )
        && builtins.isString (entry.name or null)
      then
        entry.name
      else
        null
    ) interfaceEntries
  );

  overlayNamesFromRuntime = sortedStrings (
    lib.filter (
      name: builtins.isString name && (lib.hasPrefix "overlay" name || lib.hasPrefix "ovl-" name)
    ) interfaceNamesFromRuntime
  );

  interfaceWanNames =
    if interfaceView != null && builtins.isAttrs interfaceView && interfaceView ? wanNames then
      interfaceView.wanNames
    else
      [ ];

  interfaceLanNames =
    if interfaceView != null && builtins.isAttrs interfaceView && interfaceView ? lanNames then
      interfaceView.lanNames
    else
      [ ];
in
rec {
  wanEntries =
    if interfaceView != null && builtins.isAttrs interfaceView && interfaceView ? wanEntries then
      lib.filter builtins.isAttrs interfaceView.wanEntries
    else
      [ ];

  overlayIngressNames = sortedStrings (overlayNames ++ overlayNamesFromRuntime);
  wanNames = sortedStrings (interfaceWanNames ++ wanIfs);
  lanNames = sortedStrings (interfaceLanNames ++ lanIfs);
  forwardEgressNames = sortedStrings (wanNames ++ overlayNames ++ overlayNamesFromRuntime);
  adapterNames = sortedStrings (wanNames ++ lanNames);
}
