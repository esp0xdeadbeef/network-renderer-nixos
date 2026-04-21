{
  lib,
  interfaceView ? null,
  forwardingIntent ? null,
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

  uplinkNames = if p2pNames != [ ] then p2pNames else wanNames;

  useExplicitForwarding =
    forwardingIntent != null
    && builtins.isAttrs forwardingIntent
    && (forwardingIntent.authoritativeAccessForwarding or false);

  forwardPairs =
    if useExplicitForwarding then
      forwardingIntent.accessForwardPairs or [ ]
    else
      lib.optionals (localAdapterNames != [ ] && uplinkNames != [ ]) [
        {
          "in" = localAdapterNames;
          "out" = uplinkNames;
          action = "accept";
          comment = "access-local-to-uplink";
        }
        {
          "in" = uplinkNames;
          "out" = localAdapterNames;
          action = "accept";
          comment = "access-uplink-to-local";
        }
      ];

  clampMssInterfaces =
    if useExplicitForwarding then
      forwardingIntent.accessClampMssInterfaces or [ ]
    else if p2pNames == [ ] then
      wanNames
    else
      [ ];

  inputRules = [
    ''
      icmpv6 type { nd-neighbor-solicit, nd-neighbor-advert, nd-router-solicit, nd-router-advert } accept comment "allow-ipv6-nd-ra"
    ''
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
    inherit inputRules forwardPairs clampMssInterfaces;
  }
