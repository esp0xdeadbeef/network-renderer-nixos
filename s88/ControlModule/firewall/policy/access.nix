{
  lib,
  interfaceView ? null,
  forwardingIntent ? null,
  communicationContract ? { },
  endpointMap ? { },
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

  resolveEndpoint =
    if endpointMap ? resolveEndpoint && builtins.isFunction endpointMap.resolveEndpoint then
      endpointMap.resolveEndpoint
    else
      (_: [ ]);

  resolveRelationEndpoint =
    if endpointMap ? resolveRelationEndpoint && builtins.isFunction endpointMap.resolveRelationEndpoint then
      endpointMap.resolveRelationEndpoint
    else
      (_: resolveEndpoint);

  trafficTypeDefinitions =
    if communicationContract ? trafficTypes && builtins.isList communicationContract.trafficTypes then
      builtins.listToAttrs (
        map
          (trafficType: {
            name = trafficType.name;
            value = trafficType;
          })
          (
            lib.filter (
              trafficType:
              builtins.isAttrs trafficType && trafficType ? name && builtins.isString trafficType.name
            ) communicationContract.trafficTypes
          )
      )
    else
      { };

  localSet = builtins.listToAttrs (
    map (name: {
      inherit name;
      value = true;
    }) localAdapterNames
  );

  keepLocalOnly = ifNames: lib.filter (ifName: builtins.hasAttr ifName localSet) ifNames;

  escapeComment = value: builtins.replaceStrings [ "\\" "\"" ] [ "\\\\" "\\\"" ] value;

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

  relationNameOf =
    relation:
    if relation ? id && builtins.isString relation.id then
      relation.id
    else if relation ? name && builtins.isString relation.name then
      relation.name
    else
      builtins.toJSON relation;

  relationRules =
    if communicationContract ? relations && builtins.isList communicationContract.relations then
      lib.unique (
        lib.concatMap (
          relation:
          let
            action = if (relation.action or "allow") == "deny" then "drop" else "accept";
            fromInterfaces = keepLocalOnly (resolveRelationEndpoint relation (relation.from or null));
            toInterfaces = keepLocalOnly (resolveRelationEndpoint relation (relation.to or null));
            trafficMatches = renderTrafficType (
              if relation ? trafficType && builtins.isString relation.trafficType then
                relation.trafficType
              else
                null
            );
            commentExpr =
              let
                value = relationNameOf relation;
              in
              if builtins.isString value && value != "" then " comment \"${escapeComment value}\"" else "";
          in
          if fromInterfaces == [ ] || toInterfaces == [ ] then
            [ ]
          else
            lib.concatMap (
              fromIf:
              lib.concatMap (
                toIf:
                map (
                  matchExpr:
                  let
                    matchPart = if matchExpr == "" then "" else " ${matchExpr}";
                  in
                  "iifname \"${fromIf}\" oifname \"${toIf}\"${matchPart} ${action}${commentExpr}"
                ) trafficMatches
              ) toInterfaces
            ) fromInterfaces
        ) (lib.filter builtins.isAttrs communicationContract.relations)
      )
    else
      [ ];

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
    forwardRules = relationRules;
  }
