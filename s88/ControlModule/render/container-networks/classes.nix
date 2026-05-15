{
  lib,
  common,
  containerModel,
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

  interfaceClassForRenderedName =
    renderedName:
    let
      ifName = interfaceKeyForRenderedName renderedName;
      iface = if ifName == null then { } else interfaces.${ifName} or { };
      ifaceClass = iface.interfaceClass or { };
    in
    if builtins.isAttrs ifaceClass then ifaceClass else { };

  classFlag = flag: name: (interfaceClassForRenderedName name).${flag} or false;

  isDownstreamSelectorAccessInterface = classFlag "edgeFacing";
  isDownstreamSelectorPolicyInterface = classFlag "fabricFacing";
  isUpstreamSelectorCoreInterface = classFlag "coreFacing";
  isUpstreamSelectorPolicyInterface = classFlag "exitFacing";
  isPolicyDownstreamInterface = classFlag "fabricFacing";
  isPolicyUpstreamInterface = classFlag "exitFacing";
  isOverlayInterface = classFlag "overlay";
  isCoreTransitInterface = classFlag "coreTransit";

  networkBehavior =
    if builtins.isAttrs (containerModel.networkBehavior or null) then containerModel.networkBehavior else { };

  isSelector = networkBehavior.isSelector or false;
  isUpstreamSelector = networkBehavior.isUpstreamSelector or false;
  isPolicy = networkBehavior.isPolicy or false;
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

  keepInterfaceRoutesInMain = networkBehavior.keepInterfaceRoutesInMain or true;
}
