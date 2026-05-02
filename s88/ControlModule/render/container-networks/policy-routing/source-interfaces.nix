{
  lib,
  common,
  interfaceNames,
  renderedInterfaceNames,
  upstreamLanesMatch,
  isSelector,
  isUpstreamSelector,
  isPolicy,
  isUpstreamSelectorCoreInterface,
  isUpstreamSelectorPolicyInterface,
  isPolicyDownstreamInterface,
  isPolicyUpstreamInterface,
  isOverlayInterface,
  isCoreTransitInterface,
}:

let
  inherit (common)
    downstreamPairKeyFor
    policyTenantKeyFor
    stringHasPrefix
    ;

  renderedNameFor = name: renderedInterfaceNames.${name};
in
{
  forTarget =
    targetName:
    let
      pairKey = downstreamPairKeyFor targetName;
      pairPrefix =
        if stringHasPrefix "access-" targetName then
          "policy-"
        else if stringHasPrefix "policy-" targetName then
          "access-"
        else
          null;
      tenantKey = policyTenantKeyFor targetName;
    in
    if isSelector && pairKey != null && pairPrefix != null then
      lib.filter (name: renderedNameFor name == "${pairPrefix}${pairKey}") interfaceNames
    else if isUpstreamSelector && isUpstreamSelectorCoreInterface targetName then
      lib.filter (
        name:
        isUpstreamSelectorPolicyInterface (renderedNameFor name)
        && upstreamLanesMatch targetName (renderedNameFor name)
      ) interfaceNames
    else if isUpstreamSelector && isUpstreamSelectorPolicyInterface targetName then
      lib.filter (
        name:
        isUpstreamSelectorCoreInterface (renderedNameFor name)
        && upstreamLanesMatch targetName (renderedNameFor name)
      ) interfaceNames
    else if isPolicy && tenantKey != null && isPolicyDownstreamInterface targetName then
      lib.filter (
        name:
        isPolicyDownstreamInterface (renderedNameFor name)
        || (isPolicyUpstreamInterface (renderedNameFor name)
          && policyTenantKeyFor (renderedNameFor name) == tenantKey)
      ) interfaceNames
    else if isPolicy && tenantKey != null && isPolicyUpstreamInterface targetName then
      lib.filter (
        name:
        (isPolicyDownstreamInterface (renderedNameFor name)
          && policyTenantKeyFor (renderedNameFor name) == tenantKey)
        || (isPolicyUpstreamInterface (renderedNameFor name)
          && policyTenantKeyFor (renderedNameFor name) == tenantKey)
      ) interfaceNames
    else if isOverlayInterface targetName then
      lib.unique (
        (lib.filter (name: renderedNameFor name == targetName) interfaceNames)
        ++ (lib.filter (name: isCoreTransitInterface (renderedNameFor name)) interfaceNames)
      )
    else if isCoreTransitInterface targetName then
      lib.unique (
        (lib.filter (name: renderedNameFor name == targetName) interfaceNames)
        ++ (lib.filter (name: isOverlayInterface (renderedNameFor name)) interfaceNames)
      )
    else
      lib.filter (name: renderedNameFor name == targetName) interfaceNames;
}
