{ lib }:
artifactContext:
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

  ensureBool =
    name: value:
    if builtins.isBool value then
      value
    else
      throw "network-renderer-nixos: expected ${name} to be a boolean";

  ensureInt =
    name: value:
    if builtins.isInt value then
      value
    else
      throw "network-renderer-nixos: expected ${name} to be an integer";

  context = ensureAttrs "artifactContext" artifactContext;

  runtimeTargetName =
    if context ? runtimeTargetName then
      ensureString "artifactContext.runtimeTargetName" context.runtimeTargetName
    else
      throw "network-renderer-nixos: artifactContext is missing runtimeTargetName";

  runtimeTarget =
    if context ? runtimeTarget then
      ensureAttrs "artifactContext.runtimeTarget" context.runtimeTarget
    else
      throw "network-renderer-nixos: artifactContext is missing runtimeTarget";

  forwardingIntent =
    if runtimeTarget ? forwardingIntent then
      ensureAttrs "runtime target '${runtimeTargetName}'.forwardingIntent" runtimeTarget.forwardingIntent
    else
      throw "network-renderer-nixos: runtime target '${runtimeTargetName}' is missing forwardingIntent";

  forwardingRules =
    if forwardingIntent ? rules then
      ensureList "runtime target '${runtimeTargetName}'.forwardingIntent.rules" forwardingIntent.rules
    else
      throw "network-renderer-nixos: runtime target '${runtimeTargetName}' is missing forwardingIntent.rules";

  mapRule =
    index: rule:
    let
      ruleDef = ensureAttrs "runtime target '${runtimeTargetName}'.forwardingIntent.rules[${toString index}]" rule;

      action =
        if ruleDef ? action then
          ensureString "runtime target '${runtimeTargetName}'.forwardingIntent.rules[${toString index}].action" ruleDef.action
        else
          throw "network-renderer-nixos: runtime target '${runtimeTargetName}' forwarding rule ${toString index} is missing action";

      fromInterface =
        if ruleDef ? fromInterface then
          ensureString "runtime target '${runtimeTargetName}'.forwardingIntent.rules[${toString index}].fromInterface" ruleDef.fromInterface
        else
          throw "network-renderer-nixos: runtime target '${runtimeTargetName}' forwarding rule ${toString index} is missing fromInterface";

      toInterface =
        if ruleDef ? toInterface then
          ensureString "runtime target '${runtimeTargetName}'.forwardingIntent.rules[${toString index}].toInterface" ruleDef.toInterface
        else
          throw "network-renderer-nixos: runtime target '${runtimeTargetName}' forwarding rule ${toString index} is missing toInterface";

      applyTcpMssClamp =
        if ruleDef ? applyTcpMssClamp then
          ensureBool "runtime target '${runtimeTargetName}'.forwardingIntent.rules[${toString index}].applyTcpMssClamp" ruleDef.applyTcpMssClamp
        else
          throw "network-renderer-nixos: runtime target '${runtimeTargetName}' forwarding rule ${toString index} is missing applyTcpMssClamp";

      verdict =
        if action == "accept" then
          "accept"
        else if action == "deny" then
          "drop"
        else
          throw "network-renderer-nixos: unsupported forwarding action '${action}' in runtime target '${runtimeTargetName}'";
    in
    {
      order = ensureInt "forwarding rule order" index;
      chain = "forward";
      comment = "${runtimeTargetName}-${toString index}";
      family = "any";
      iifname = fromInterface;
      oifname = toInterface;
      saddr4s = [ ];
      saddr6s = [ ];
      daddr4s = [ ];
      daddr6s = [ ];
      proto = null;
      dports = [ ];
      applyTcpMssClamp = applyTcpMssClamp;
      verdict = verdict;
    };

  rules = lib.imap0 mapRule forwardingRules;

  _haveRules =
    if rules == [ ] then
      throw "network-renderer-nixos: runtime target '${runtimeTargetName}' has no forwarding rules"
    else
      true;
in
builtins.seq _haveRules {
  inherit runtimeTargetName;
  tableFamily = "inet";
  tableName = "filter";
  chains = {
    forward = {
      type = "filter";
      hook = "forward";
      priority = 0;
      policy = "drop";
      rules = rules;
    };
  };
}
