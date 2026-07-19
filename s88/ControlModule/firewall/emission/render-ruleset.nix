{ lib }:

{
  tableName ? "router",
  inputPolicy ? "accept",
  outputPolicy ? "accept",
  forwardPolicy ? "drop",
  forwardPairs ? [ ],
  forwardRules ? [ ],
  inputRules ? [ ],
  outputRules ? [ ],
  natInterfaces ? [ ],
  nat4SourcePrefixes ? [ ],
  nat6Interfaces ? [ ],
  nat6SourcePrefixes ? [ ],
  natPreroutingRules4 ? [ ],
  natPreroutingRules6 ? [ ],
  natPostroutingRules4 ? [ ],
  natPostroutingRules6 ? [ ],
  clampMssInterfaces ? [ ],
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
  escapeComment = value: builtins.replaceStrings [ "\\" "\"" ] [ "\\\\" "\\\"" ] value;
  renderComment = value: escapeComment (builtins.substring 0 nftCommentLimit value);

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
      # Fail-closed placeholder. The runtime service replaces this exact rule
      # in place, preserving the CPM-defined rule order.
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
      action = if rawAction == "deny" then "drop" else rawAction;

      customMatches =
        if pair ? match && builtins.isString pair.match && pair.match != "" then [ pair.match ] else [ "" ];

      connectionStateExpr =
        if
          pair ? connectionState && builtins.isString pair.connectionState && pair.connectionState != ""
        then
          " ct state ${pair.connectionState}"
        else
          "";

      sourceMatches = sourcePrefixMatches pair;
      destinationMatches = destinationPrefixMatches pair;
      rawMatches =
        if pair ? matches && builtins.isList pair.matches && pair.matches != [ ] then
          lib.concatMap renderRawMatch (lib.filter builtins.isAttrs pair.matches)
        else
          [ "" ];

      matchExprs = combineMatches (combineMatches (combineMatches customMatches sourceMatches) destinationMatches) rawMatches;

      commentExpr =
        if pair ? comment && builtins.isString pair.comment && pair.comment != "" then
          " comment \"${renderComment pair.comment}\""
        else
          "";
    in
    map (
      matchPart:
      "iifname ${renderIfExpr inIfs} oifname ${renderIfExpr outIfs}${
        lib.optionalString (matchPart != "") " ${matchPart}"
      }${connectionStateExpr} ${action}${commentExpr}"
    ) matchExprs;

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
  postrouting4 = lib.filter (rule: builtins.isString rule && rule != "") natPostroutingRules4;
  postrouting6 = lib.filter (rule: builtins.isString rule && rule != "") natPostroutingRules6;
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
+ lib.optionalString (natIfs4 != [ ] || prerouting4 != [ ] || postrouting4 != [ ]) ''

    table ip nat {
      chain prerouting {
        type nat hook prerouting priority -100; policy accept;
    ${renderChainRules prerouting4}  }

  ${lib.optionalString (natIfs4 != [ ] || postrouting4 != [ ]) ''
      chain postrouting {
        type nat hook postrouting priority 100; policy accept;
    ${
      lib.optionalString (natIfs4 != [ ])
        "    oifname ${renderIfExpr natIfs4}${
              lib.optionalString (nat4Sources != [ ]) " ip saddr ${renderValueExpr nat4Sources}"
            } masquerade\n"
    }${renderChainRules postrouting4}  }
  ''}
    }
''
+ lib.optionalString (natIfs6 != [ ] || prerouting6 != [ ] || postrouting6 != [ ]) ''

    table ip6 nat {
      chain prerouting {
        type nat hook prerouting priority -100; policy accept;
    ${renderChainRules prerouting6}  }

  ${lib.optionalString (natIfs6 != [ ] || postrouting6 != [ ]) ''
      chain postrouting {
        type nat hook postrouting priority 100; policy accept;
    ${
      lib.optionalString (natIfs6 != [ ])
        "    oifname ${renderIfExpr natIfs6}${
              lib.optionalString (nat6Sources != [ ]) " ip6 saddr ${renderValueExpr nat6Sources}"
            } masquerade\n"
    }${renderChainRules postrouting6}  }
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
