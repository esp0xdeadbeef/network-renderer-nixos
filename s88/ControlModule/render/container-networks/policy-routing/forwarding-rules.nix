{
  lib,
  containerModel,
  forwardingIntent ? null,
}:
let
  forwardingIntentData =
    if forwardingIntent != null && builtins.isAttrs forwardingIntent then forwardingIntent else { };

  runtimeForwardingIntent =
    if builtins.isAttrs ((containerModel.runtimeTarget or { }).forwardingIntent or null) then
      containerModel.runtimeTarget.forwardingIntent
    else
      { };

  explicitPairsToRules =
    pairs:
    lib.concatMap (
      pair:
      if !(builtins.isAttrs pair) || (pair.action or "accept") != "accept" then
        [ ]
      else
        lib.concatMap (
          fromInterface:
          map (
            toInterface:
            {
              action = "accept";
              inherit fromInterface toInterface;
            }
            // lib.optionalAttrs (builtins.isList (pair.sourcePrefixes or null)) {
              inherit (pair) sourcePrefixes;
            }
            // lib.optionalAttrs (builtins.isList (pair.sourceFiles or null)) {
              inherit (pair) sourceFiles;
            }
            // lib.optionalAttrs (builtins.isInt (pair.family or null)) {
              inherit (pair) family;
            }
            // lib.optionalAttrs (builtins.isString (pair.trafficType or null) && pair.trafficType != "") {
              inherit (pair) trafficType;
            }
            // lib.optionalAttrs (builtins.isList (pair.match or null) && pair.match != [ ]) {
              inherit (pair) match;
            }
          ) (pair."out" or [ ])
        ) (pair."in" or [ ])
    ) pairs;

  explicitForwardingRules =
    (runtimeForwardingIntent.rules or [ ])
    ++ (forwardingIntentData.rules or [ ])
    ++ (explicitPairsToRules (runtimeForwardingIntent.normalizedExplicitForwardPairs or [ ]))
    ++ (explicitPairsToRules (forwardingIntentData.normalizedExplicitForwardPairs or [ ]));

  forwardingRulesResolved =
    if explicitForwardingRules != [ ] then
      explicitForwardingRules
    else
      explicitPairsToRules (forwardingIntentData.policyRelationForwardPairs or [ ]);

  routeFamily =
    route:
    if
      (route.family or null) == 4 || (route.dst or null) == "0.0.0.0/0" || (route.via4 or null) != null
    then
      4
    else if
      (route.family or null) == 6
      || (route.dst or null) == "::/0"
      || (route.dst or null) == "0000:0000:0000:0000:0000:0000:0000:0000/0"
      || (route.via6 or null) != null
    then
      6
    else
      null;

  ruleMatchesFamily =
    rule: route:
    let
      expectedFamily = routeFamily route;
      ruleFamily = rule.family or null;
    in
    expectedFamily == null || ruleFamily == null || ruleFamily == expectedFamily;

  matchingAcceptForwardingRules =
    fromName: toName:
    lib.filter (
      rule:
      builtins.isAttrs rule
      && (rule.action or null) == "accept"
      && (rule.fromInterface or null) == fromName
      && (rule.toInterface or null) == toName
    ) forwardingRulesResolved;
in
{
  inherit forwardingRulesResolved;

  hasAcceptForwardingRule = fromName: toName: matchingAcceptForwardingRules fromName toName != [ ];

  hasAcceptForwardingRuleForRoute =
    fromName: toName: route:
    builtins.any (rule: ruleMatchesFamily rule route) (matchingAcceptForwardingRules fromName toName);
}
