{
  lib,
  common,
  resolveInterfaceTokens,
  runtimeTarget,
  nodeForwarding,
}:

let
  inherit (common) asList valuesFromPaths attrOr;

  normalizeAction =
    raw:
    if raw == "deny" || raw == "drop" then
      "drop"
    else if raw == "allow" || raw == "accept" then
      "accept"
    else
      raw;

  normalizeForwardPair =
    pair:
    if !builtins.isAttrs pair then
      null
    else
      let
        inIfs = resolveInterfaceTokens (
          (attrOr pair "in" [ ]) ++ (attrOr pair "iifname" [ ]) ++ (attrOr pair "from" [ ])
        );
        outIfs = resolveInterfaceTokens (
          (attrOr pair "out" [ ]) ++ (attrOr pair "oifname" [ ]) ++ (attrOr pair "to" [ ])
        );
        action = normalizeAction (
          if pair ? action && builtins.isString pair.action then pair.action else "accept"
        );
      in
      if inIfs == [ ] || outIfs == [ ] then
        null
      else
        {
          "in" = inIfs;
          "out" = outIfs;
          inherit action;
        }
        // lib.optionalAttrs (pair ? comment && builtins.isString pair.comment && pair.comment != "") {
          comment = pair.comment;
        };

  recognizedConnectionStates = [ "established,related" ];

  normalizeForwardRule =
    rule:
    if !builtins.isAttrs rule then
      null
    else
      let
        inIfs = resolveInterfaceTokens (attrOr rule "fromInterface" [ ]);
        outIfs = resolveInterfaceTokens (attrOr rule "toInterface" [ ]);
        action = normalizeAction (
          if rule ? action && builtins.isString rule.action then rule.action else "accept"
        );
        comment =
          if builtins.isString (rule.relationId or null) then
            rule.relationId
          else if builtins.isString (rule.comment or null) then
            rule.comment
          else
            null;
        ruleName = if comment != null && comment != "" then comment else builtins.toJSON rule;
        isReturnRule = (rule.returnRule or null) == true || (rule.direction or null) == "relation-reverse";
        connectionState =
          if builtins.isString (rule.connectionState or null) && rule.connectionState != "" then
            rule.connectionState
          else
            null;
        _validateReturnRule =
          if isReturnRule && connectionState == null then
            throw "FS-230-HDS-010-SDS-010-SMS-030: reverse return rule '${ruleName}' carries no connection-state restriction (reverse-new-flow authority invention); encode stateful return via connectionState or model a distinct, independently authorized reverse relation"
          else if connectionState != null && !(builtins.elem connectionState recognizedConnectionStates) then
            throw "FS-230-HDS-010-SDS-010-SMS-030: rule '${ruleName}' carries an unrecognized connectionState '${connectionState}'; recognized values: ${builtins.concatStringsSep ", " recognizedConnectionStates}"
          else
            true;
      in
      if inIfs == [ ] || outIfs == [ ] then
        null
      else
        builtins.seq _validateReturnRule {
          "in" = inIfs;
          "out" = outIfs;
          inherit action;
        }
        // lib.optionalAttrs (connectionState != null) {
          inherit connectionState;
        }
        // lib.optionalAttrs isReturnRule {
          returnRule = true;
        }
        // lib.optionalAttrs (builtins.isString (rule.trafficType or null)) {
          trafficType = rule.trafficType;
        }
        // lib.optionalAttrs (builtins.isList (rule.sourceFiles or null)) {
          sourceFiles = lib.filter (value: builtins.isString value && value != "") rule.sourceFiles;
        }
        // lib.optionalAttrs (builtins.isList (rule.sourcePrefixes or null)) {
          sourcePrefixes = lib.filter (
            value:
            (builtins.isString value && value != "")
            || (builtins.isAttrs value && builtins.isString (value.prefix or null) && value.prefix != "")
          ) rule.sourcePrefixes;
        }
        // lib.optionalAttrs (builtins.isList (rule.destinationPrefixes or null)) {
          destinationPrefixes = lib.filter (
            value:
            (builtins.isString value && value != "")
            || (builtins.isAttrs value && builtins.isString (value.prefix or null) && value.prefix != "")
          ) rule.destinationPrefixes;
        }
        // lib.optionalAttrs (builtins.isList (rule.matches or null)) {
          matches = lib.filter builtins.isAttrs rule.matches;
        }
        // lib.optionalAttrs (builtins.isInt (rule.family or null)) {
          family = rule.family;
        }
        // lib.optionalAttrs (comment != null && comment != "") {
          inherit comment;
        };

  fromRules = lib.filter (pair: pair != null) (
    map normalizeForwardRule (
      if
        builtins.elem (nodeForwarding.mode or null) [
          "explicit-access-forwarding"
          "explicit-core-forwarding"
          "explicit-selector-forwarding"
          "explicit-policy-forwarding"
        ]
        && nodeForwarding ? rules
        && builtins.isList nodeForwarding.rules
      then
        lib.filter builtins.isAttrs nodeForwarding.rules
      else
        [ ]
    )
  );

  fromPairs = lib.filter (pair: pair != null) (
    map normalizeForwardPair (
      lib.concatMap asList (valuesFromPaths {
        roots = [
          runtimeTarget
          nodeForwarding
        ];
        paths = [
          [ "forwardPairs" ]
          [
            "firewall"
            "forwardPairs"
          ]
          [
            "forwarding"
            "forwardPairs"
          ]
          [
            "forwarding"
            "firewall"
            "forwardPairs"
          ]
        ];
      })
    )
  );
in
if fromRules != [ ] then fromRules else fromPairs
