{ lib
, containerModel
, forwardingIntent ? null
,
}:
let
  forwardingIntentData =
    if forwardingIntent != null && builtins.isAttrs forwardingIntent then
      forwardingIntent
    else
      { };

  runtimeForwardingIntent =
    if builtins.isAttrs ((containerModel.runtimeTarget or { }).forwardingIntent or null) then
      containerModel.runtimeTarget.forwardingIntent
    else
      { };

  explicitPairsToRules =
    pairs:
    lib.concatMap
      (
        pair:
        if !(builtins.isAttrs pair) || (pair.action or "accept") != "accept" then
          [ ]
        else
          lib.concatMap
            (
              fromInterface:
              map
                (toInterface: {
                  action = "accept";
                  inherit fromInterface toInterface;
                })
                (pair."out" or [ ])
            )
            (pair."in" or [ ])
      )
      pairs;

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
in
{
  inherit forwardingRulesResolved;

  hasAcceptForwardingRule =
    fromName: toName:
    builtins.any
      (rule:
      builtins.isAttrs rule
      && (rule.action or null) == "accept"
      && (rule.fromInterface or null) == fromName
      && (rule.toInterface or null) == toName)
      forwardingRulesResolved;
}
