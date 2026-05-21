{
  isSelector,
  isPolicy,
  isDownstreamSelectorPolicyInterface,
  isPolicyUpstreamInterface,
}:

let
  emptyScope = {
    staticPrefixes = [ ];
    sourceFiles = [ ];
  };

  isReturnSideInterface =
    interfaceName:
    (isSelector && isDownstreamSelectorPolicyInterface interfaceName)
    || (isPolicy && isPolicyUpstreamInterface interfaceName);
in
{
  forInterface =
    interfaceName: sourceScope:
    if isReturnSideInterface interfaceName then emptyScope else sourceScope;
}
