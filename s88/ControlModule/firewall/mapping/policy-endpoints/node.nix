{
  lib,
  currentSite,
  runtimeTarget,
  roleName,
  interfaceEntries,
  common,
}:

let
  inherit (common) sortedStrings entryFieldOr;

  currentSiteNodes =
    if currentSite ? nodes && builtins.isAttrs currentSite.nodes then currentSite.nodes else { };

  runtimeLogicalNodeName =
    if
      runtimeTarget ? interfaces
      && builtins.isAttrs runtimeTarget.interfaces
      && runtimeTarget.interfaces != { }
    then
      let
        names = sortedStrings (
          map (
            ifName:
            let
              iface = runtimeTarget.interfaces.${ifName};
            in
            if iface ? logicalNode && builtins.isString iface.logicalNode then iface.logicalNode else null
          ) (builtins.attrNames runtimeTarget.interfaces)
        );
      in
      if builtins.length names == 1 then builtins.head names else null
    else
      null;

  currentNodeName =
    if runtimeLogicalNodeName != null then
      runtimeLogicalNodeName
    else if
      roleName == "policy"
      && currentSite ? policyNodeName
      && builtins.isString currentSite.policyNodeName
      && currentSite.policyNodeName != ""
    then
      currentSite.policyNodeName
    else
      let
        names = sortedStrings (map (entry: entryFieldOr entry "logicalNode" null) interfaceEntries);
      in
      if builtins.length names == 1 then builtins.head names else null;

  currentNode =
    if
      builtins.hasAttr currentNodeName currentSiteNodes
      && builtins.isAttrs currentSiteNodes.${currentNodeName}
    then
      currentSiteNodes.${currentNodeName}
    else
      { };
in
{
  inherit currentNodeName currentNode;

  currentNodeInterfaces =
    if currentNode ? interfaces && builtins.isAttrs currentNode.interfaces then
      currentNode.interfaces
    else
      { };
}
