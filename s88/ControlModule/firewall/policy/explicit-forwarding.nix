{
  lib,
  escapeComment,
  renderTrafficType ? (_: [ "" ]),
  forwardingIntent ? null,
  shouldRenderPair ? (_: true),
}:

let
  asList =
    value:
    if value == null then
      [ ]
    else if builtins.isList value then
      value
    else
      [ value ];

  sortedStrings =
    values:
    lib.sort builtins.lessThan (
      lib.unique (lib.filter (value: builtins.isString value && value != "") (asList values))
    );
  nftCommentLimit = 128;
  renderComment = value: escapeComment (builtins.substring 0 nftCommentLimit value);

  renderInterfaceExpr =
    ifaces:
    let
      names = sortedStrings ifaces;
    in
    if names == [ ] then
      throw "s88/ControlModule/firewall/policy/explicit-forwarding.nix: empty explicit policy forwarding interface set"
    else if builtins.length names == 1 then
      "\"${builtins.head names}\""
    else
      "{ ${builtins.concatStringsSep ", " (map (name: "\"${name}\"") names)} }";

  sourcePrefixMatch =
    value:
    let
      prefix = if builtins.isString value then value else value.prefix or "";
      family =
        if builtins.isAttrs value && (value.family or null) == 6 then
          6
        else if builtins.isString prefix && lib.hasInfix ":" prefix then
          6
        else
          4;
    in
    if !(builtins.isString prefix) || prefix == "" then
      null
    else if family == 6 then
      "ip6 saddr ${prefix}"
    else
      "ip saddr ${prefix}";

  sourcePrefixMatches =
    pair:
    lib.filter (value: value != null) (map sourcePrefixMatch (asList (pair.sourcePrefixes or [ ])));

  destinationPrefixMatch =
    value:
    let
      prefix = if builtins.isString value then value else value.prefix or "";
      family =
        if builtins.isAttrs value && (value.family or null) == 6 then
          6
        else if builtins.isString prefix && lib.hasInfix ":" prefix then
          6
        else
          4;
    in
    if !(builtins.isString prefix) || prefix == "" then
      null
    else if family == 6 then
      "ip6 daddr ${prefix}"
    else
      "ip daddr ${prefix}";

  destinationPrefixMatches =
    pair:
    let
      static = lib.filter (value: value != null) (
        map destinationPrefixMatch (asList (pair.destinationPrefixes or [ ]))
      );
      runtime = asList (pair.destinationRuntimeAddresses or [ ]);
      validRuntime =
        builtins.length runtime == 1
        && builtins.isAttrs (builtins.head runtime)
        && ((builtins.head runtime).sourceClass or null) == "protected"
        && builtins.isString ((builtins.head runtime).sourceFile or null)
        && lib.hasPrefix "/run/secrets/" (builtins.head runtime).sourceFile
        && ((builtins.head runtime).targetPrefixLength or null) == 128;
    in
    if runtime == [ ] then
      static
    else if static != [ ] || !validRuntime then
      throw "FS-230-HDS-010-SDS-010-SMS-040: runtime IPv6 destination must be one protected /128 source with no static destination"
    else
      [ "ip6 daddr ::/128" ];

  renderRawMatch =
    match:
    let
      family = if builtins.isString (match.family or null) then match.family else "any";
      proto = if builtins.isString (match.proto or null) then match.proto else null;
      dports = lib.filter builtins.isInt (asList (match.dports or [ ]));
      familyPrefix =
        if family == "ipv4" then
          "meta nfproto ipv4 "
        else if family == "ipv6" then
          "meta nfproto ipv6 "
        else
          "";
      portExpr =
        if
          dports == [ ]
          || !(builtins.elem proto [
            "tcp"
            "udp"
          ])
        then
          ""
        else
          " ${proto} dport { ${builtins.concatStringsSep ", " (map builtins.toString dports)} }";
    in
    if proto == null || proto == "any" then
      [ familyPrefix ]
    else if proto == "icmp" then
      if family == "ipv6" then
        [ "meta nfproto ipv6 ip6 nexthdr ipv6-icmp" ]
      else
        [ "${familyPrefix}ip protocol icmp" ]
    else if proto == "icmpv6" || proto == "icmp6" then
      [ "meta nfproto ipv6 ip6 nexthdr ipv6-icmp" ]
    else
      [ "${familyPrefix}meta l4proto ${proto}${portExpr}" ];

  combineMatches =
    left: right:
    if left == [ ] then
      right
    else if right == [ ] then
      left
    else
      lib.concatMap (
        leftMatch:
        map (
          rightMatch:
          if leftMatch == "" then
            rightMatch
          else if rightMatch == "" then
            leftMatch
          else
            "${leftMatch} ${rightMatch}"
        ) right
      ) left;

  explicitForwardPairs =
    if forwardingIntent != null && builtins.isAttrs forwardingIntent then
      forwardingIntent.normalizedExplicitForwardPairs or [ ]
    else
      [ ];

  renderExplicitForwardPair =
    pair:
    let
      rawAction = if pair ? action && builtins.isString pair.action then pair.action else "accept";
      action =
        if rawAction == "deny" || rawAction == "drop" then
          "drop"
        else if rawAction == "allow" || rawAction == "accept" then
          "accept"
        else
          rawAction;

      connectionStateExpr =
        if
          pair ? connectionState && builtins.isString pair.connectionState && pair.connectionState != ""
        then
          " ct state ${pair.connectionState}"
        else
          "";
      commentExpr =
        if pair ? comment && builtins.isString pair.comment && pair.comment != "" then
          " comment \"${renderComment pair.comment}\""
        else
          "";
      rawMatches =
        if pair ? matches && builtins.isList pair.matches && pair.matches != [ ] then
          lib.concatMap renderRawMatch (lib.filter builtins.isAttrs pair.matches)
        else if pair ? trafficType && builtins.isString pair.trafficType then
          renderTrafficType pair.trafficType
        else
          [ "" ];
      scopedMatches = combineMatches (combineMatches (sourcePrefixMatches pair) (destinationPrefixMatches pair)) rawMatches;
      trafficMatches =
        if pair ? sourceFiles && builtins.isList pair.sourceFiles && pair.sourceFiles != [ ] then
          [ "__s88_dynamic_source_forward__" ] ++ scopedMatches
        else
          scopedMatches;
    in
    map (
      matchExpr:
      let
        matchPart = if matchExpr == "" then "" else " ${matchExpr}";
      in
      if matchExpr == "__s88_dynamic_source_forward__" then
        ""
      else
        "iifname ${renderInterfaceExpr (pair."in" or [ ])} oifname ${
          renderInterfaceExpr (pair."out" or [ ])
        }${matchPart}${connectionStateExpr} ${action}${commentExpr}"
    ) trafficMatches;
in
lib.filter (rule: rule != "") (
  lib.concatMap renderExplicitForwardPair (
    lib.filter (pair: builtins.isAttrs pair && shouldRenderPair pair) explicitForwardPairs
  )
)
