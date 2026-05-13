{
  common,
  renderedInterfaceNames,
  isSelector,
  isUpstreamSelector,
  isPolicy,
  isDownstreamSelectorAccessInterface,
  isDownstreamSelectorPolicyInterface,
  isUpstreamSelectorCoreInterface,
  isUpstreamSelectorPolicyInterface,
  isPolicyDownstreamInterface,
  isPolicyUpstreamInterface,
  upstreamLanesMatch,
}:

{
  mayProject =
    targetName: sourceIfName:
    let
      sourceName = renderedInterfaceNames.${sourceIfName};
      targetPairKey = common.downstreamPairKeyFor targetName;
      sourcePairKey = common.downstreamPairKeyFor sourceName;
    in
    (
      isPolicy
      && isPolicyDownstreamInterface targetName
      && isPolicyUpstreamInterface sourceName
      && common.policyTenantKeyFor targetName != null
      && common.policyTenantKeyFor targetName == common.policyTenantKeyFor sourceName
    )
    || (
      isUpstreamSelector
      && isUpstreamSelectorPolicyInterface targetName
      && isUpstreamSelectorCoreInterface sourceName
      && upstreamLanesMatch targetName sourceName
    )
    || (
      isSelector
      && isDownstreamSelectorAccessInterface targetName
      && isDownstreamSelectorPolicyInterface sourceName
      && targetPairKey != null
      && targetPairKey == sourcePairKey
    );
}
