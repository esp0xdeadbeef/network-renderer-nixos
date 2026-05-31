{ lib }:

{ tableName ? "router"
, inputPolicy ? "accept"
, outputPolicy ? "accept"
, forwardPolicy ? "drop"
, forwardPairs ? [ ]
, forwardRules ? [ ]
, inputRules ? [ ]
, outputRules ? [ ]
, natInterfaces ? [ ]
, nat4SourcePrefixes ? [ ]
, nat6Interfaces ? [ ]
, nat6SourcePrefixes ? [ ]
, natPreroutingRules4 ? [ ]
, natPreroutingRules6 ? [ ]
, clampMssInterfaces ? [ ]
,
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

  escapeComment = value: builtins.replaceStrings [ "\\" "\"" ] [ "\\\\" "\\\"" ] value;

  renderIfExpr =
    ifaces:
    let
      names = sortedStrings ifaces;
    in
    if names == [ ] then
      abort "s88/ControlModule/firewall/emission/render-ruleset.nix: empty interface expression"
    else if builtins.length names == 1 then
      "\"${builtins.head names}\""
    else
      "{ ${builtins.concatStringsSep ", " (map (name: "\"${name}\"") names)} }";

  renderValueExpr =
    values:
    let
      names = sortedStrings values;
    in
    if names == [ ] then
      abort "s88/ControlModule/firewall/emission/render-ruleset.nix: empty value expression"
    else if builtins.length names == 1 then
      builtins.head names
    else
      "{ ${builtins.concatStringsSep ", " names} }";

  attrOr =
    name: fallback: attrs:
    if builtins.isAttrs attrs && builtins.hasAttr name attrs then attrs.${name} else fallback;

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

  renderPairRules =
    pair:
    let
      inIfs =
        let
          fromIn = attrOr "in" null pair;
        in
        if fromIn != null then fromIn else attrOr "iifname" null pair;

      outIfs =
        let
          fromOut = attrOr "out" null pair;
        in
        if fromOut != null then fromOut else attrOr "oifname" null pair;

      rawAction = if pair ? action && builtins.isString pair.action then pair.action else "accept";
      action =
        if rawAction == "deny" then
          "drop"
        else
          rawAction;

      matchExpr =
        if pair ? match && builtins.isString pair.match && pair.match != "" then " ${pair.match}" else "";

      sourceMatches = sourcePrefixMatches pair;

      matchExprs =
        if sourceMatches != [ ] then
          map (sourceMatch: "${matchExpr} ${sourceMatch}") sourceMatches
        else
          [ matchExpr ];

      commentExpr =
        if pair ? comment && builtins.isString pair.comment && pair.comment != "" then
          " comment \"${escapeComment pair.comment}\""
        else
          "";
    in
    map
      (matchPart: "iifname ${renderIfExpr inIfs} oifname ${renderIfExpr outIfs}${matchPart} ${action}${commentExpr}")
      matchExprs;

  renderedForwardRules = lib.unique (
    (lib.concatMap renderPairRules forwardPairs)
    ++ (lib.filter (rule: builtins.isString rule && rule != "") forwardRules)
  );

  renderChainRules =
    rules:
    if rules == [ ] then
      ""
    else
      "${builtins.concatStringsSep "\n" (map (rule: "    ${rule}") rules)}\n";

  natIfs4 = sortedStrings natInterfaces;
  nat4Sources = sortedStrings nat4SourcePrefixes;
  natIfs6 = sortedStrings nat6Interfaces;
  nat6Sources = sortedStrings nat6SourcePrefixes;
  prerouting4 = lib.filter (rule: builtins.isString rule && rule != "") natPreroutingRules4;
  prerouting6 = lib.filter (rule: builtins.isString rule && rule != "") natPreroutingRules6;
  clampIfs = sortedStrings clampMssInterfaces;
in
''
  table inet ${tableName} {
    chain input {
      type filter hook input priority filter; policy ${inputPolicy};
      iifname "lo" accept
      ct state established,related accept
  ${renderChainRules inputRules}  }

    chain forward {
      type filter hook forward priority filter; policy ${forwardPolicy};
      ct state invalid drop
      ct state established,related accept
  ${renderChainRules renderedForwardRules}  }

    chain output {
      type filter hook output priority filter; policy ${outputPolicy};
  ${renderChainRules outputRules}  }
  }
''
+ lib.optionalString (natIfs4 != [ ] || prerouting4 != [ ]) ''

    table ip nat {
      chain prerouting {
        type nat hook prerouting priority -100; policy accept;
    ${renderChainRules prerouting4}  }

  ${lib.optionalString (natIfs4 != [ ]) ''
    chain postrouting {
      type nat hook postrouting priority 100; policy accept;
      oifname ${renderIfExpr natIfs4}${lib.optionalString (nat4Sources != [ ]) " ip saddr ${renderValueExpr nat4Sources}"} masquerade
    }
  ''}
    }
''
+ lib.optionalString (natIfs6 != [ ] || prerouting6 != [ ]) ''

    table ip6 nat {
      chain prerouting {
        type nat hook prerouting priority -100; policy accept;
    ${renderChainRules prerouting6}  }

  ${lib.optionalString (natIfs6 != [ ]) ''
    chain postrouting {
      type nat hook postrouting priority 100; policy accept;
      oifname ${renderIfExpr natIfs6}${lib.optionalString (nat6Sources != [ ]) " ip6 saddr ${renderValueExpr nat6Sources}"} masquerade
    }
  ''}
    }
''
  + lib.optionalString (clampIfs != [ ]) ''

  table inet mangle {
    chain forward {
      type filter hook forward priority mangle; policy accept;
      oifname ${renderIfExpr clampIfs} tcp flags syn tcp option maxseg size set rt mtu
    }
  }
''
