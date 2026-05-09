{
  lib,
  common,
  interfaces,
  interfaceNames,
  renderedInterfaceNames,
}:

let
  inherit (common) stringHasPrefix;
  interfaceKeyForRenderedName =
    renderedName:
    lib.findFirst (
      ifName: ifName == renderedName || renderedInterfaceNames.${ifName} == renderedName
    ) null interfaceNames;

  backingRefFor =
    iface:
    if iface ? backingRef && builtins.isAttrs iface.backingRef then
      iface.backingRef
    else if
      iface ? connectivity
      && builtins.isAttrs iface.connectivity
      && iface.connectivity ? backingRef
      && builtins.isAttrs iface.connectivity.backingRef
    then
      iface.connectivity.backingRef
    else
      { };

  laneForRenderedName =
    renderedName:
    let
      ifName = interfaceKeyForRenderedName renderedName;
      iface = if ifName == null then { } else interfaces.${ifName} or { };
      backingRef = backingRefFor iface;
    in
    if builtins.isString (backingRef.lane or null) then backingRef.lane else "";

  isDownstreamSelectorAccessInterface = name: stringHasPrefix "access-" name;
  isDownstreamSelectorPolicyInterface = name: stringHasPrefix "policy-" name;
  isUpstreamSelectorCoreInterface =
    name:
    (stringHasPrefix "core-" name || name == "upstream" || stringHasPrefix "upstream-" name)
    && (builtins.match "uplink::.*" (laneForRenderedName name)) != null;
  isUpstreamSelectorPolicyInterface =
    name: stringHasPrefix "pol-" name || stringHasPrefix "policy-" name;
  isPolicyDownstreamInterface =
    name:
    stringHasPrefix "downstr-" name
    || stringHasPrefix "downstream-" name
    || stringHasPrefix "down-" name;
  isPolicyUpstreamInterface = name: stringHasPrefix "up-" name || stringHasPrefix "upstream-" name;
  isOverlayInterface = name: stringHasPrefix "overlay-" name;
  isCoreTransitInterface = name: name == "upstream" || stringHasPrefix "upstream-" name;

  isSelector =
    lib.any (name: isDownstreamSelectorAccessInterface renderedInterfaceNames.${name}) interfaceNames
    && lib.any (
      name: isDownstreamSelectorPolicyInterface renderedInterfaceNames.${name}
    ) interfaceNames;

  isUpstreamSelector =
    lib.any (name: isUpstreamSelectorCoreInterface renderedInterfaceNames.${name}) interfaceNames
    && lib.any (name: isUpstreamSelectorPolicyInterface renderedInterfaceNames.${name}) interfaceNames;

  isPolicy =
    lib.any (name: isPolicyDownstreamInterface renderedInterfaceNames.${name}) interfaceNames
    && lib.any (name: isPolicyUpstreamInterface renderedInterfaceNames.${name}) interfaceNames;
in
{
  inherit
    isSelector
    isUpstreamSelector
    isPolicy
    isDownstreamSelectorAccessInterface
    isDownstreamSelectorPolicyInterface
    isUpstreamSelectorCoreInterface
    isUpstreamSelectorPolicyInterface
    isPolicyDownstreamInterface
    isPolicyUpstreamInterface
    isOverlayInterface
    isCoreTransitInterface
    ;

  keepInterfaceRoutesInMain = !(isSelector || isUpstreamSelector || isPolicy);
}
