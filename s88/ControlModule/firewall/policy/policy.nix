{
  lib,
  communicationContract ? { },
  endpointMap ? { },
  ...
}:

let
  escapeComment = value: builtins.replaceStrings [ "\\" "\"" ] [ "\\\\" "\\\"" ] value;

  resolveEndpoint =
    if endpointMap ? resolveEndpoint && builtins.isFunction endpointMap.resolveEndpoint then
      endpointMap.resolveEndpoint
    else
      (_: [ ]);

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

  relations =
    if communicationContract ? relations && builtins.isList communicationContract.relations then
      lib.sort (
        left: right:
        let
          leftPriority = if left ? priority && builtins.isInt left.priority then left.priority else 1000;
          rightPriority = if right ? priority && builtins.isInt right.priority then right.priority else 1000;
        in
        leftPriority < rightPriority
      ) (lib.filter builtins.isAttrs communicationContract.relations)
    else
      [ ];

  relationNameOf =
    relation:
    if relation ? id && builtins.isString relation.id then
      relation.id
    else if relation ? name && builtins.isString relation.name then
      relation.name
    else
      builtins.toJSON relation;

  relationRenderings = map (
    relation:
    let
      action = if (relation.action or "allow") == "deny" then "drop" else "accept";

      fromInterfaces = resolveEndpoint (relation.from or null);
      toInterfaces = resolveEndpoint (relation.to or null);

      trafficMatches = renderTrafficType (
        if relation ? trafficType && builtins.isString relation.trafficType then
          relation.trafficType
        else
          null
      );

      commentValue = relationNameOf relation;

      commentExpr =
        if builtins.isString commentValue && commentValue != "" then
          " comment \"${escapeComment commentValue}\""
        else
          "";

      rules = lib.concatMap (
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
      ) fromInterfaces;
    in
    {
      name = relationNameOf relation;
      inherit
        relation
        fromInterfaces
        toInterfaces
        rules
        ;
    }
  ) relations;

  renderedRules = lib.unique (lib.concatMap (rendering: rendering.rules) relationRenderings);

  _validateCommunicationContract =
    if communicationContract != { } then
      true
    else
      throw ''
        s88/ControlModule/firewall/policy/policy.nix: missing communication contract for policy role
      '';

  _validateRelations =
    if relations != [ ] then
      true
    else
      throw ''
        s88/ControlModule/firewall/policy/policy.nix: policy role requires non-empty communicationContract.relations
      '';

  _validateRelationEndpoints = builtins.foldl' (
    acc: rendering:
    builtins.seq acc (
      if rendering.fromInterfaces == [ ] then
        throw ''
          s88/ControlModule/firewall/policy/policy.nix: relation '${rendering.name}' resolved no source interfaces

          relation:
          ${builtins.toJSON rendering.relation}
        ''
      else if rendering.toInterfaces == [ ] then
        throw ''
          s88/ControlModule/firewall/policy/policy.nix: relation '${rendering.name}' resolved no destination interfaces

          relation:
          ${builtins.toJSON rendering.relation}
        ''
      else
        true
    )
  ) true relationRenderings;

  _validateRenderedRules =
    if renderedRules != [ ] then
      true
    else
      throw ''
        s88/ControlModule/firewall/policy/policy.nix: policy role rendered zero firewall rules
      '';

  output = {
    tableName = "router";
    inputPolicy = "drop";
    outputPolicy = "accept";
    forwardPolicy = "drop";
    forwardRules = renderedRules;
  };
in
builtins.seq _validateCommunicationContract (
  builtins.seq _validateRelations (
    builtins.seq _validateRelationEndpoints (builtins.seq _validateRenderedRules output)
  )
)
