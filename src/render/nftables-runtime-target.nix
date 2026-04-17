{ lib }:
firewallModel:
let
  ensureAttrs =
    name: value:
    if builtins.isAttrs value then
      value
    else
      throw "network-renderer-nixos: expected ${name} to be an attribute set";

  ensureList =
    name: value:
    if builtins.isList value then
      value
    else
      throw "network-renderer-nixos: expected ${name} to be a list";

  ensureString =
    name: value:
    if builtins.isString value && value != "" then
      value
    else
      throw "network-renderer-nixos: expected ${name} to be a non-empty string";

  ensureInt =
    name: value:
    if builtins.isInt value then
      value
    else
      throw "network-renderer-nixos: expected ${name} to be an integer";

  ensureBool =
    name: value:
    if builtins.isBool value then
      value
    else
      throw "network-renderer-nixos: expected ${name} to be a boolean";

  model = ensureAttrs "firewallModel" firewallModel;

  tableFamily =
    if model ? tableFamily then
      ensureString "firewallModel.tableFamily" model.tableFamily
    else
      throw "network-renderer-nixos: firewallModel is missing tableFamily";

  tableName =
    if model ? tableName then
      ensureString "firewallModel.tableName" model.tableName
    else
      throw "network-renderer-nixos: firewallModel is missing tableName";

  chains =
    if model ? chains then
      ensureAttrs "firewallModel.chains" model.chains
    else
      throw "network-renderer-nixos: firewallModel is missing chains";

  escapeString =
    value:
    builtins.replaceStrings
      [
        "\\"
        "\""
        "\n"
        "\r"
        "\t"
      ]
      [
        "\\\\"
        "\\\""
        "\\n"
        "\\r"
        "\\t"
      ]
      value;

  sortedChainNames = lib.sort builtins.lessThan (builtins.attrNames chains);

  renderSet = values: "{ ${lib.concatStringsSep ", " values} }";

  renderFamilyAddressClauses =
    rule:
    if rule.family == "ipv4" then
      (lib.optional (rule.saddr4s != [ ]) "ip saddr ${renderSet rule.saddr4s}")
      ++ (lib.optional (rule.daddr4s != [ ]) "ip daddr ${renderSet rule.daddr4s}")
    else if rule.family == "ipv6" then
      (lib.optional (rule.saddr6s != [ ]) "ip6 saddr ${renderSet rule.saddr6s}")
      ++ (lib.optional (rule.daddr6s != [ ]) "ip6 daddr ${renderSet rule.daddr6s}")
    else if rule.family == "any" then
      [ ]
    else
      throw "network-renderer-nixos: unsupported firewall rule family '${rule.family}'";

  renderProtoClauses =
    rule:
    let
      proto = rule.proto;
      dports = rule.dports;
    in
    if proto == null then
      if dports == [ ] then
        [ ]
      else
        throw "network-renderer-nixos: firewall rule cannot define dports without proto"
    else if proto == "tcp" then
      [ "meta l4proto tcp" ]
      ++ (lib.optional (dports != [ ]) "tcp dport ${renderSet (map toString dports)}")
    else if proto == "udp" then
      [ "meta l4proto udp" ]
      ++ (lib.optional (dports != [ ]) "udp dport ${renderSet (map toString dports)}")
    else if proto == "icmp" then
      if dports != [ ] then
        throw "network-renderer-nixos: ICMP firewall rule cannot define dports"
      else if rule.family == "ipv4" then
        [ "meta l4proto icmp" ]
      else if rule.family == "ipv6" then
        [ "meta l4proto ipv6-icmp" ]
      else
        throw "network-renderer-nixos: ICMP firewall rule requires family ipv4 or ipv6"
    else
      throw "network-renderer-nixos: unsupported firewall protocol '${proto}'";

  renderRule =
    rule:
    let
      ruleDef = ensureAttrs "firewall chain rule" rule;
      iifname =
        if ruleDef ? iifname then
          ensureString "firewall chain rule.iifname" ruleDef.iifname
        else
          throw "network-renderer-nixos: firewall chain rule is missing iifname";

      oifname =
        if ruleDef ? oifname then
          ensureString "firewall chain rule.oifname" ruleDef.oifname
        else
          throw "network-renderer-nixos: firewall chain rule is missing oifname";

      family =
        if ruleDef ? family then
          ensureString "firewall chain rule.family" ruleDef.family
        else
          throw "network-renderer-nixos: firewall chain rule is missing family";

      verdict =
        if ruleDef ? verdict then
          ensureString "firewall chain rule.verdict" ruleDef.verdict
        else
          throw "network-renderer-nixos: firewall chain rule is missing verdict";

      comment =
        if ruleDef ? comment then ensureString "firewall chain rule.comment" ruleDef.comment else null;

      applyTcpMssClamp =
        if ruleDef ? applyTcpMssClamp then
          ensureBool "firewall chain rule.applyTcpMssClamp" ruleDef.applyTcpMssClamp
        else
          false;

      saddr4s =
        if ruleDef ? saddr4s then ensureList "firewall chain rule.saddr4s" ruleDef.saddr4s else [ ];

      saddr6s =
        if ruleDef ? saddr6s then ensureList "firewall chain rule.saddr6s" ruleDef.saddr6s else [ ];

      daddr4s =
        if ruleDef ? daddr4s then ensureList "firewall chain rule.daddr4s" ruleDef.daddr4s else [ ];

      daddr6s =
        if ruleDef ? daddr6s then ensureList "firewall chain rule.daddr6s" ruleDef.daddr6s else [ ];

      proto = if ruleDef ? proto then ruleDef.proto else null;

      dports = if ruleDef ? dports then ensureList "firewall chain rule.dports" ruleDef.dports else [ ];

      normalizedRule = {
        inherit
          family
          saddr4s
          saddr6s
          daddr4s
          daddr6s
          proto
          dports
          ;
      };

      matchClauses = [
        "iifname \"${escapeString iifname}\""
        "oifname \"${escapeString oifname}\""
      ]
      ++ renderFamilyAddressClauses normalizedRule
      ++ renderProtoClauses normalizedRule
      ++ (lib.optional applyTcpMssClamp "tcp flags syn tcp option maxseg size set rt mtu");

      tailClauses = [
        "counter"
        verdict
      ]
      ++ (lib.optional (comment != null) "comment \"${escapeString comment}\"");
    in
    "    ${lib.concatStringsSep " " (matchClauses ++ tailClauses)};";

  renderAutomaticForwardRules =
    chainName:
    let
      chain = ensureAttrs "firewallModel.chains.${chainName}" chains.${chainName};

      hook =
        if chain ? hook then
          ensureString "firewallModel.chains.${chainName}.hook" chain.hook
        else
          throw "network-renderer-nixos: firewall chain '${chainName}' is missing hook";
    in
    if hook == "forward" then
      [
        "    ct state invalid counter drop;"
        "    ct state established,related counter accept;"
      ]
    else
      [ ];

  renderChain =
    chainName:
    let
      chain = ensureAttrs "firewallModel.chains.${chainName}" chains.${chainName};

      chainType =
        if chain ? type then
          ensureString "firewallModel.chains.${chainName}.type" chain.type
        else
          throw "network-renderer-nixos: firewall chain '${chainName}' is missing type";

      hook =
        if chain ? hook then
          ensureString "firewallModel.chains.${chainName}.hook" chain.hook
        else
          throw "network-renderer-nixos: firewall chain '${chainName}' is missing hook";

      priority =
        if chain ? priority then
          ensureInt "firewallModel.chains.${chainName}.priority" chain.priority
        else
          throw "network-renderer-nixos: firewall chain '${chainName}' is missing priority";

      policy =
        if chain ? policy then
          ensureString "firewallModel.chains.${chainName}.policy" chain.policy
        else
          throw "network-renderer-nixos: firewall chain '${chainName}' is missing policy";

      rules =
        if chain ? rules then
          ensureList "firewallModel.chains.${chainName}.rules" chain.rules
        else
          throw "network-renderer-nixos: firewall chain '${chainName}' is missing rules";

      renderedRules = map renderRule rules;
    in
    lib.concatStringsSep "\n" (
      [
        "  chain ${chainName} {"
        "    type ${chainType} hook ${hook} priority ${toString priority}; policy ${policy};"
      ]
      ++ renderAutomaticForwardRules chainName
      ++ renderedRules
      ++ [ "  }" ]
    );
in
lib.concatStringsSep "\n" (
  [
    "flush ruleset"
    ""
    "table ${tableFamily} ${tableName} {"
  ]
  ++ (map renderChain sortedChainNames)
  ++ [
    "}"
    ""
  ]
)
