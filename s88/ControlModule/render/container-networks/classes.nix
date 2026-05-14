{
  lib,
  common,
  interfaces,
  interfaceNames,
  renderedInterfaceNames,
}:

let
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

  backingRefForRenderedName =
    renderedName:
    let
      ifName = interfaceKeyForRenderedName renderedName;
      iface = if ifName == null then { } else interfaces.${ifName} or { };
    in
    backingRefFor iface;

  laneForRenderedName =
    renderedName:
    let
      lane = (backingRefForRenderedName renderedName).lane or { };
    in
    if builtins.isAttrs lane then lane else { };

  laneKindForRenderedName = name: (laneForRenderedName name).kind or null;

  isDownstreamSelectorAccessInterface = name: laneKindForRenderedName name == "access-edge";
  isDownstreamSelectorPolicyInterface = name: laneKindForRenderedName name == "access";
  isUpstreamSelectorCoreInterface = name: laneKindForRenderedName name == "uplink";
  isUpstreamSelectorPolicyInterface = name: laneKindForRenderedName name == "access-uplink";
  isPolicyDownstreamInterface = name: laneKindForRenderedName name == "access";
  isPolicyUpstreamInterface = name: laneKindForRenderedName name == "access-uplink";
  isOverlayInterface = name: (backingRefForRenderedName name).kind or null == "overlay";
  isCoreTransitInterface = name: laneKindForRenderedName name == "uplink";

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
