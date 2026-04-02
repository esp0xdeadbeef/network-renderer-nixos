{
  lib,
  interfaceView ? null,
  topology ? null,
  ...
}:

let
  sortedStrings =
    values:
    lib.sort builtins.lessThan (
      lib.unique (lib.filter (value: builtins.isString value && value != "") values)
    );

  interfaceEntries =
    if interfaceView != null && builtins.isAttrs interfaceView && interfaceView ? interfaceEntries then
      interfaceView.interfaceEntries
    else
      [ ];

  wanNames =
    if interfaceView != null && builtins.isAttrs interfaceView && interfaceView ? wanNames then
      sortedStrings interfaceView.wanNames
    else
      [ ];

  sourceKindOf =
    entry:
    if entry ? sourceKind && builtins.isString entry.sourceKind then
      entry.sourceKind
    else if
      entry ? iface
      && builtins.isAttrs entry.iface
      && entry.iface ? sourceKind
      && builtins.isString entry.iface.sourceKind
    then
      entry.iface.sourceKind
    else
      null;

  p2pNames = sortedStrings (
    map (entry: entry.name) (lib.filter (entry: sourceKindOf entry == "p2p") interfaceEntries)
  );

  localAdapterNames = sortedStrings (
    map (entry: entry.name) (
      lib.filter (
        entry:
        let
          sourceKind = sourceKindOf entry;
        in
        sourceKind != "wan" && sourceKind != "p2p"
      ) interfaceEntries
    )
  );

  transitNames = if p2pNames != [ ] then p2pNames else wanNames;

  transitMeshPairs =
    if builtins.length transitNames < 2 then
      [ ]
    else
      lib.concatMap (
        inIf:
        map (outIf: {
          "in" = [ inIf ];
          "out" = [ outIf ];
          action = "accept";
          comment = "policy-${inIf}-to-${outIf}";
        }) (lib.filter (candidate: candidate != inIf) transitNames)
      ) transitNames;

  localTransitPairs = lib.optionals (localAdapterNames != [ ] && transitNames != [ ]) [
    {
      "in" = localAdapterNames;
      "out" = transitNames;
      action = "accept";
      comment = "policy-local-to-transit";
    }
    {
      "in" = transitNames;
      "out" = localAdapterNames;
      action = "accept";
      comment = "policy-transit-to-local";
    }
  ];
in
if interfaceEntries == [ ] then
  null
else
  {
    tableName = "router";
    inputPolicy = "drop";
    outputPolicy = "accept";
    forwardPolicy = "drop";
    forwardPairs = transitMeshPairs ++ localTransitPairs;
  }
