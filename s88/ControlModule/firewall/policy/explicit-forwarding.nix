{ lib, escapeComment, renderTrafficType ? (_: [ "" ]), forwardingIntent ? null }:

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
        if rawAction == "deny" then
          "drop"
        else
          rawAction;
      commentExpr =
        if pair ? comment && builtins.isString pair.comment && pair.comment != "" then
          " comment \"${escapeComment pair.comment}\""
        else
          "";
      trafficMatches =
        if pair ? sourceFiles && builtins.isList pair.sourceFiles && pair.sourceFiles != [ ] then
          [ "__s88_dynamic_source_forward__" ]
        else if pair ? trafficType && builtins.isString pair.trafficType then
          renderTrafficType pair.trafficType
        else
          [ "" ];
    in
    map
      (matchExpr:
        let matchPart = if matchExpr == "" then "" else " ${matchExpr}";
        in
        if matchExpr == "__s88_dynamic_source_forward__" then
          ""
        else
          "iifname ${renderInterfaceExpr (pair."in" or [ ])} oifname ${renderInterfaceExpr (pair."out" or [ ])}${matchPart} ${action}${commentExpr}")
      trafficMatches;
in
lib.filter (rule: rule != "") (lib.concatMap renderExplicitForwardPair (lib.filter (pair: builtins.isAttrs pair) explicitForwardPairs))
