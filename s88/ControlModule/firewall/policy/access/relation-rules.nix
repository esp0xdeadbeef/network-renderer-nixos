{ lib
, communicationContract
, endpointMap
, keepLocalOnly
,
}:

let
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
in
if communicationContract ? relations && builtins.isList communicationContract.relations then
  lib.unique
    (
      lib.concatMap
        (
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
            lib.concatMap
              (
                fromIf:
                lib.concatMap
                  (
                    toIf:
                    map
                      (
                        matchExpr:
                        let
                          matchPart = if matchExpr == "" then "" else " ${matchExpr}";
                        in
                        "iifname \"${fromIf}\" oifname \"${toIf}\"${matchPart} ${action}${commentExpr}"
                      )
                      trafficMatches
                  )
                  toInterfaces
              )
              fromInterfaces
        )
        (lib.filter builtins.isAttrs communicationContract.relations)
    )
else
  [ ]
