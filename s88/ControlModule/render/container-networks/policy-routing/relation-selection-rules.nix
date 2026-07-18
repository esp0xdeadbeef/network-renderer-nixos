{ lib
, interfaces
, renderedInterfaceNames
, routeSelectionRules
,
}:

let
  traceId = "FS-270-HDS-010-SDS-010-SMS-020";
  interfaceNames = builtins.attrNames interfaces;

  matchesIdentity =
    identity: ifName:
    let
      iface = interfaces.${ifName};
      aliases = if builtins.isList (iface.interfaceAliases or null) then iface.interfaceAliases else [ ];
    in
    ifName == identity
    || renderedInterfaceNames.${ifName} == identity
    || builtins.elem identity aliases;

  interfaceKeyForIdentity =
    field: identity:
    let
      matches = lib.filter (matchesIdentity identity) interfaceNames;
    in
    if !(builtins.isString identity) || identity == "" then
      throw "${traceId}: route selector '${field}' must be a non-empty explicit interface identity"
    else if builtins.length matches != 1 then
      throw "${traceId}: route selector '${field}' must resolve to exactly one rendered interface"
    else
      builtins.head matches;

  positiveInt =
    field: value:
    if builtins.isInt value && value > 0 then
      value
    else
      throw "${traceId}: route selector '${field}' must be a positive integer";

  requiredString =
    field: value:
    if builtins.isString value && value != "" then
      value
    else
      throw "${traceId}: route selector '${field}' must be a non-empty string";

  entryFor =
    selector:
    let
      _shape =
        if !(builtins.isAttrs selector) then
          throw "${traceId}: routeSelectionRules entries must be attribute sets"
        else if (selector.authority or null) != "relation-policy-state-owner" then
          throw "${traceId}: route selector must carry relation-policy-state-owner authority"
        else if !(builtins.elem (selector.direction or null) [ "forward" "return" ]) then
          throw "${traceId}: route selector direction must be forward or return"
        else if !(builtins.elem (selector.family or null) [ 4 6 ]) then
          throw "${traceId}: route selector family must be 4 or 6"
        else if !(builtins.elem (selector.returnBehavior or null) [ "symmetric" "stateful-return" ]) then
          throw "${traceId}: route selector must preserve stateful return behavior"
        else
          true;
      incomingKey = interfaceKeyForIdentity "incomingInterface" (selector.incomingInterface or null);
      policyKey = interfaceKeyForIdentity "policyInterface" (selector.policyInterface or null);
      allocation = interfaces.${policyKey}.policyRoutingAllocation or null;
      _allocation =
        if !(builtins.isAttrs allocation) then
          throw "${traceId}: selected policy interface lacks CPM policyRoutingAllocation"
        else if (allocation.source or null) != "control-plane-model" then
          throw "${traceId}: selected policy table is not owned by the control-plane model"
        else
          true;
      tableId = positiveInt "tableId" (selector.tableId or null);
      priority = positiveInt "priority" (selector.priority or null);
      allocationTableId = positiveInt "policyRoutingAllocation.tableId" (allocation.tableId or null);
      genericPriority = positiveInt "policyRoutingAllocation.tableRulePriority" (allocation.tableRulePriority or null);
      _tableBinding =
        if tableId != allocationTableId then
          throw "${traceId}: route selector table does not match its explicit policy interface allocation"
        else if priority >= genericPriority then
          throw "${traceId}: relation selector must precede the generic policy-routing selector"
        else
          true;
      sourcePrefix = requiredString "sourcePrefix" (selector.sourcePrefix or null);
      destinationPrefix = requiredString "destinationPrefix" (selector.destinationPrefix or null);
      _relation = requiredString "relationId" (selector.relationId or null);
      _stateOwner = requiredString "policyStateOwner" (selector.policyStateOwner or null);
      _trafficType = requiredString "trafficType" (selector.trafficType or null);
      _service = requiredString "service" (selector.service or null);
      _bounded =
        if builtins.elem sourcePrefix [ "0.0.0.0/0" "::/0" ] || builtins.elem destinationPrefix [ "0.0.0.0/0" "::/0" ] then
          throw "${traceId}: lateral service route selector must not grant default or transitive egress authority"
        else
          true;
      routes = interfaces.${policyKey}.routes or [ ];
      routeList =
        if builtins.isList routes then
          routes
        else if builtins.isAttrs routes then
          (if builtins.isList (routes.ipv4 or null) then routes.ipv4 else [ ])
          ++ (if builtins.isList (routes.ipv6 or null) then routes.ipv6 else [ ])
        else
          [ ];
      hasSelectedRoute = builtins.any
        (
          route:
          builtins.isAttrs route
          && (route.policyOnly or false)
          && (route.dst or null) == destinationPrefix
          && (route.relationId or null) == selector.relationId
          && (route.intent.kind or null) == "relation-policy-reachability"
          && (route.intent.direction or null) == selector.direction
          && (route.intent.policyStateOwner or null) == selector.policyStateOwner
          && (
            (selector.family == 4 && builtins.isString (route.via4 or null))
            || (selector.family == 6 && builtins.isString (route.via6 or null))
          )
        )
        routeList;
      _routeBinding =
        if hasSelectedRoute then
          true
        else
          throw "${traceId}: route selector lacks its exact CPM policy-table reachability route";
    in
    builtins.seq _shape (
      builtins.seq _allocation (
        builtins.seq _tableBinding (
          builtins.seq _relation (
            builtins.seq _stateOwner (
              builtins.seq _trafficType (
                builtins.seq _service (
                  builtins.seq _bounded (
                    builtins.seq _routeBinding {
                      name = incomingKey;
                      value = {
                        Family = if selector.family == 4 then "ipv4" else "ipv6";
                        From = sourcePrefix;
                        To = destinationPrefix;
                        IncomingInterface = renderedInterfaceNames.${incomingKey};
                        Priority = priority;
                        Table = tableId;
                      };
                    }
                  )
                )
              )
            )
          )
        )
      )
    );

  entries = map entryFor routeSelectionRules;
  ruleKeys = lib.unique (map (entry: entry.name) entries);
in
{
  rulesByInterface = builtins.listToAttrs (
    map
      (ifName: {
        name = ifName;
        value = lib.unique (map (entry: entry.value) (lib.filter (entry: entry.name == ifName) entries));
      })
      ruleKeys
  );
}
