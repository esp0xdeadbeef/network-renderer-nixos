{ lib, lookup, naming }:

let
  inherit (naming) validInterfaceName;
in
{
  sourceKindForInterface =
    iface:
    if iface ? connectivity && builtins.isAttrs iface.connectivity && builtins.isString (iface.connectivity.sourceKind or null) then
      iface.connectivity.sourceKind
    else if iface ? sourceKind && builtins.isString iface.sourceKind then
      iface.sourceKind
    else
      null;

  attachTargetForInterface =
    { unitName, ifName, iface }:
    let
      matches = lib.filter
        (
          target:
          (target.unitName or null) == unitName
          && (
            (target.ifName or null) == ifName
            || ((target.renderedIfName or null) == (iface.renderedIfName or null))
            || ((target.interface.renderedIfName or null) == (iface.renderedIfName or null))
            || ((target.hostBridgeName or null) == (iface.hostBridge or null))
          )
        )
        lookup.localAttachTargets;
    in
    if builtins.length matches == 1 then
      builtins.head matches
    else if builtins.hasAttr (iface.hostBridge or "") lookup.bridgeNameMap then
      {
        renderedHostBridgeName = lookup.bridgeNameMap.${iface.hostBridge};
        assignedUplinkName = null;
        identity = { };
      }
    else
      # Fallback: try to match via attachTarget hostBridgeName 
      let
        fallbackMatches = lib.filter
          (target: target ? hostBridgeName && builtins.isString target.hostBridgeName
            && builtins.stringLength (iface.hostBridge or "") > 0
            && lib.hasSuffix (iface.hostBridge or "") (target.hostBridgeName or ""))
          lookup.localAttachTargets;
      in
      if builtins.length fallbackMatches >= 1 then
        (builtins.head fallbackMatches) // {
          renderedHostBridgeName = (builtins.head fallbackMatches).hostBridgeName;
        }
      else
        builtins.trace
          "WARNING: could not resolve rendered host bridge for '${unitName}/${ifName}' (hostBridge=${iface.hostBridge or "null"}) — skipping"
          null;

  interfaceNameFromAttachTarget =
    attachTarget:
    if
      attachTarget ? identity
      && builtins.isAttrs attachTarget.identity
      && attachTarget.identity ? portName
      && validInterfaceName attachTarget.identity.portName
    then
      attachTarget.identity.portName
    else
      null;

  interfaceNameFromUpstream =
    iface:
    if iface ? connectivity && builtins.isAttrs iface.connectivity && validInterfaceName (iface.connectivity.upstream or null) then
      iface.connectivity.upstream
    else
      null;
}
