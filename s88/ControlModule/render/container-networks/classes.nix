{
  lib,
  common,
  interfaceNames,
  renderedInterfaceNames,
}:

let
  inherit (common) stringHasPrefix;

  isDownstreamSelectorAccessInterface = name: stringHasPrefix "access-" name;
  isDownstreamSelectorPolicyInterface = name: stringHasPrefix "policy-" name;
  isUpstreamSelectorCoreInterface = name: name == "core" || stringHasPrefix "core-" name;
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
