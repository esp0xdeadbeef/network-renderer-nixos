{ lib
, communicationContract ? { }
, interfaceView ? null
, forwardingIntent ? null
, ...
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

  entryByName = builtins.listToAttrs (map (entry: { name = entry.name; value = entry; }) interfaceEntries);

  interfaceClassFor =
    name:
    let
      entry = entryByName.${name} or { };
      iface = entry.iface or { };
      ifaceClass = iface.interfaceClass or { };
    in
    if builtins.isAttrs ifaceClass then ifaceClass else { };

  isCoreFacing =
    name:
    let ifaceClass = interfaceClassFor name;
    in (ifaceClass.coreFacing or false) || (ifaceClass.coreTransit or false);

  isCoreScopedSourceForward =
    pair:
    pair ? sourcePrefixes
    && builtins.isList pair.sourcePrefixes
    && pair.sourcePrefixes != [ ]
    && builtins.all isCoreFacing (pair."in" or [ ])
    && builtins.all isCoreFacing (pair."out" or [ ]);

  useExplicitForwarding =
    forwardingIntent != null
    && builtins.isAttrs forwardingIntent
    && (forwardingIntent.authoritativeUpstreamSelectorForwarding or false);

  escapeComment = value: builtins.replaceStrings [ "\\" "\"" ] [ "\\\\" "\\\"" ] value;

  trafficTypeDefinitions =
    if communicationContract ? trafficTypes && builtins.isList communicationContract.trafficTypes then
      builtins.listToAttrs
        (
          map
            (trafficType: {
              name = trafficType.name;
              value = trafficType;
            })
            (
              lib.filter
                (
                  trafficType:
                  builtins.isAttrs trafficType && trafficType ? name && builtins.isString trafficType.name
                )
                communicationContract.trafficTypes
            )
        )
    else
      { };

  renderMatch =
    match:
    let
      family = if match ? family && builtins.isString match.family then match.family else "any";
      proto = if match ? proto && builtins.isString match.proto then match.proto else null;
      dports =
        if match ? dports && builtins.isList match.dports then
          lib.filter builtins.isInt match.dports
        else
          [ ];
      portExpr =
        if dports == [ ] then
          ""
        else
          " ${proto} dport { ${builtins.concatStringsSep ", " (map builtins.toString dports)} }";
      familyPrefix =
        if family == "ipv4" then
          "meta nfproto ipv4 "
        else if family == "ipv6" then
          "meta nfproto ipv6 "
        else
          "";
    in
    if proto == null || proto == "any" then
      [ "" ]
    else if proto == "icmp" then
      if family == "ipv4" then
        [ "meta nfproto ipv4 ip protocol icmp" ]
      else if family == "ipv6" then
        [ "meta nfproto ipv6 ip6 nexthdr ipv6-icmp" ]
      else
        [
          "meta nfproto ipv4 ip protocol icmp"
          "meta nfproto ipv6 ip6 nexthdr ipv6-icmp"
        ]
    else if proto == "icmpv6" || proto == "icmp6" then
      [ "meta nfproto ipv6 ip6 nexthdr ipv6-icmp" ]
    else if proto == "tcp" || proto == "udp" then
      [ "${familyPrefix}meta l4proto ${proto}${portExpr}" ]
    else
      [ "${familyPrefix}meta l4proto ${proto}" ];

  renderTrafficType =
    trafficTypeName:
    if trafficTypeName == null || trafficTypeName == "any" then
      [ "" ]
    else if builtins.hasAttr trafficTypeName trafficTypeDefinitions then
      let
        trafficType = trafficTypeDefinitions.${trafficTypeName};
        matches =
          if trafficType ? match && builtins.isList trafficType.match then trafficType.match else [ ];
      in
      if matches == [ ] then [ "" ] else lib.concatMap renderMatch matches
    else
      [ "" ];

  forwardRules =
    if useExplicitForwarding then
      import ./explicit-forwarding.nix
        {
          inherit
            lib
            escapeComment
            renderTrafficType
            forwardingIntent
            ;
          shouldRenderPair = pair: !(isCoreScopedSourceForward pair);
        }
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
    inherit inputRules forwardRules;
  }
