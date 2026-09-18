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
    else if
      !(builtins.isInt (selection.mainSelectionPriority or null)) || selection.mainSelectionPriority <= 0
    then
      throw "${traceId}: targetOriginatedSelection.mainSelectionPriority must be a positive integer"
    else if !(builtins.isInt (selection.selectionPriority or null)) || selection.selectionPriority <= 0 then
      throw "${traceId}: targetOriginatedSelection.selectionPriority must be a positive integer"
    else if selection.selectionPriority <= selection.mainSelectionPriority then
      throw "${traceId}: targetOriginatedSelection context selection must follow the main fallthrough"
    else
      true;

  # Connected/local routes must win for the target's own traffic (its on-link
  # fabric peers live in the main table). The main fallthrough selection
  # returns no route for prefixes main does not own and the kernel then tries
  # the context-table selection, which carries the modeled reachability.
  rules = [
    {
      Family = "both";
      Priority = selection.mainSelectionPriority;
      Table = 254;
    }
    {
      Family = "both";
      Priority = selection.selectionPriority;
      Table = selection.tableId;
    }
  ];

  rule = rules;
in
builtins.seq _shape {
  rulesByInterface =
    if selection == null then
      { }
    else
      {
        ${ownerInterfaceForKey} = rules;
      };
}
