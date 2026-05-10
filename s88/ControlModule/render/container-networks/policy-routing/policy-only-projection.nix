{
  common,
  renderedInterfaceNames,
  isSelector,
  isPolicy,
  isDownstreamSelectorAccessInterface,
  isDownstreamSelectorPolicyInterface,
  isPolicyDownstreamInterface,
  isPolicyUpstreamInterface,
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
      isSelector
      && isDownstreamSelectorAccessInterface targetName
      && isDownstreamSelectorPolicyInterface sourceName
      && targetPairKey != null
      && targetPairKey == sourcePairKey
    );
}
