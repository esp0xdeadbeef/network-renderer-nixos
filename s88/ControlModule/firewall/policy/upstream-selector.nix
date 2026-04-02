{
  lib,
  interfaceView ? null,
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

  transitNames = sortedStrings (
    map (entry: entry.name) (lib.filter (entry: sourceKindOf entry == "p2p") interfaceEntries)
  );

  forwardPairs =
    if builtins.length transitNames < 2 then
      [ ]
    else
      lib.concatMap (
        inIf:
        map (outIf: {
          "in" = [ inIf ];
          "out" = [ outIf ];
          action = "accept";
          comment = "upstream-selector-${inIf}-to-${outIf}";
        }) (lib.filter (candidate: candidate != inIf) transitNames)
      ) transitNames;
in
if interfaceEntries == [ ] then
  null
else
  {
    tableName = "router";
    inputPolicy = "drop";
    outputPolicy = "accept";
    forwardPolicy = "drop";
    inherit forwardPairs;
  }
