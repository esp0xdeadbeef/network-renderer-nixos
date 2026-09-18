{ lib
, interfaces
, renderedInterfaceNames
, targetOriginatedSelection
,
}:

# FS-315-HDS-010-SDS-010-SMS-020: the modeled target-originated selection.
#
# A lookup the runtime target originates itself -- a hop-generated ICMP error --
# carries no ingress selector, so no ingress-scoped rule matches it. The control
# plane model names a context table and priority for that lookup as data; the
# renderer installs exactly that rule and invents no fallback of its own. The
# rule is installed once on the interface whose allocation owns the selected
# table.
let
  traceId = "FS-315-HDS-010-SDS-010-SMS-020";
  interfaceNames = builtins.attrNames interfaces;

  selection = targetOriginatedSelection;

  ownerInterfaceForKey =
    let
      named = selection.ownerInterface or null;
      byName =
        if builtins.isString named && builtins.hasAttr named interfaces then
          [ named ]
        else
          [ ];
      byTable = lib.filter
        (
          ifName:
          (interfaces.${ifName}.policyRoutingAllocation.tableId or null) == selection.tableId
        )
        interfaceNames;
      matches = if byName != [ ] then byName else byTable;
    in
    if builtins.length matches >= 1 then
      builtins.head matches
    else
      throw "${traceId}: target-originated selection does not resolve to a rendered interface";

  _shape =
    if !(builtins.isAttrs selection) then
      throw "${traceId}: targetOriginatedSelection must be an attribute set"
    else if (selection.source or null) != "control-plane-model" then
      throw "${traceId}: targetOriginatedSelection.source must be 'control-plane-model'"
    else if !(builtins.isInt (selection.tableId or null)) || selection.tableId <= 0 then
      throw "${traceId}: targetOriginatedSelection.tableId must be a positive integer"
    else if !(builtins.isInt (selection.priority or null)) || selection.priority <= 0 then
      throw "${traceId}: targetOriginatedSelection.priority must be a positive integer"
    else
      true;

  rule = {
    Family = "both";
    Priority = selection.priority;
    Table = selection.tableId;
  };
in
builtins.seq _shape {
  rulesByInterface =
    if selection == null then
      { }
    else
      {
        ${ownerInterfaceForKey} = [ rule ];
      };
}
