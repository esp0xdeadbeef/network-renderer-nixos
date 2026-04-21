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

  attrOr =
    name: fallback: attrs:
    if builtins.isAttrs attrs && builtins.hasAttr name attrs then attrs.${name} else fallback;

  renderPairRule =
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

      action = if pair ? action && builtins.isString pair.action then pair.action else "accept";

      matchExpr =
        if pair ? match && builtins.isString pair.match && pair.match != "" then " ${pair.match}" else "";

      commentExpr =
        if pair ? comment && builtins.isString pair.comment && pair.comment != "" then
          " comment \"${escapeComment pair.comment}\""
        else
          "";
    in
    "iifname ${renderIfExpr inIfs} oifname ${renderIfExpr outIfs}${matchExpr} ${action}${commentExpr}";

  renderedForwardRules = lib.unique (
    (map renderPairRule forwardPairs)
    ++ (lib.filter (rule: builtins.isString rule && rule != "") forwardRules)
  );

  renderChainRules =
    rules:
    if rules == [ ] then
      ""
    else
      "${builtins.concatStringsSep "\n" (map (rule: "    ${rule}") rules)}\n";

  natIfs = sortedStrings natInterfaces;
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
+ lib.optionalString (natIfs != [ ]) ''

  table ip nat {
    chain postrouting {
      type nat hook postrouting priority 100; policy accept;
      oifname ${renderIfExpr natIfs} masquerade
    }
  }
''
+ lib.optionalString (natIfs != [ ]) ''

  table ip6 nat {
    chain postrouting {
      type nat hook postrouting priority 100; policy accept;
      oifname ${renderIfExpr natIfs} masquerade
    }
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
