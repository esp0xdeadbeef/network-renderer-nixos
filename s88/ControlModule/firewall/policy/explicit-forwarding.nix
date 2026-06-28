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

  combineMatches = left: right:
    if left == [ ] then
      right
    else if right == [ ] then
      left
    else
      lib.concatMap
        (leftMatch:
          map
            (rightMatch:
              if leftMatch == "" then
                rightMatch
              else if rightMatch == "" then
                leftMatch
              else
                "${leftMatch} ${rightMatch}")
            right)
        left;

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
      commentExpr =
        if pair ? comment && builtins.isString pair.comment && pair.comment != "" then
          " comment \"${renderComment pair.comment}\""
        else
          "";
      trafficMatches =
        if pair ? sourceFiles && builtins.isList pair.sourceFiles && pair.sourceFiles != [ ] then
          [ "__s88_dynamic_source_forward__" ]
          ++ combineMatches
            (sourcePrefixMatches pair)
            (if pair ? trafficType && builtins.isString pair.trafficType then renderTrafficType pair.trafficType else [ "" ])
        else if
          pair ? sourcePrefixes && builtins.isList pair.sourcePrefixes && pair.sourcePrefixes != [ ]
        then
          combineMatches
            (sourcePrefixMatches pair)
            (if pair ? trafficType && builtins.isString pair.trafficType then renderTrafficType pair.trafficType else [ "" ])
        else if pair ? trafficType && builtins.isString pair.trafficType then
          renderTrafficType pair.trafficType
        else
          [ "" ];
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
        }${matchPart} ${action}${commentExpr}"
    ) trafficMatches;
in
lib.filter (rule: rule != "") (
  lib.concatMap renderExplicitForwardPair (
    lib.filter (pair: builtins.isAttrs pair && shouldRenderPair pair) explicitForwardPairs
  )
)
