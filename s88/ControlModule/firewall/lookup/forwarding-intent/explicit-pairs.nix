{ lib, common, resolveInterfaceTokens, runtimeTarget, nodeForwarding }:

let
  inherit (common) asList valuesFromPaths attrOr;

  normalizeForwardPair =
    pair:
    if !builtins.isAttrs pair then
      null
    else
      let
        inIfs = resolveInterfaceTokens ((attrOr pair "in" [ ]) ++ (attrOr pair "iifname" [ ]) ++ (attrOr pair "from" [ ]));
        outIfs = resolveInterfaceTokens ((attrOr pair "out" [ ]) ++ (attrOr pair "oifname" [ ]) ++ (attrOr pair "to" [ ]));
        action = if pair ? action && builtins.isString pair.action then pair.action else "accept";
      in
      if inIfs == [ ] || outIfs == [ ] then null else {
        "in" = inIfs;
        "out" = outIfs;
        inherit action;
      } // lib.optionalAttrs (pair ? comment && builtins.isString pair.comment && pair.comment != "") {
        comment = pair.comment;
      };

  normalizeForwardRule =
    rule:
    if !builtins.isAttrs rule then
      null
    else
      let
        inIfs = resolveInterfaceTokens (attrOr rule "fromInterface" [ ]);
        outIfs = resolveInterfaceTokens (attrOr rule "toInterface" [ ]);
        action = if rule ? action && builtins.isString rule.action then rule.action else "accept";
      in
      if inIfs == [ ] || outIfs == [ ] then null else { "in" = inIfs; "out" = outIfs; inherit action; };

  fromRules = lib.filter (pair: pair != null) (
    map normalizeForwardRule (
      if nodeForwarding ? rules && builtins.isList nodeForwarding.rules then lib.filter builtins.isAttrs nodeForwarding.rules else [ ]
    )
  );

  fromPairs = lib.filter (pair: pair != null) (
    map normalizeForwardPair (
      lib.concatMap asList (valuesFromPaths {
        roots = [ runtimeTarget nodeForwarding ];
        paths = [
          [ "forwardPairs" ] [ "firewall" "forwardPairs" ] [ "policy" "forwardPairs" ]
          [ "forwarding" "forwardPairs" ] [ "forwarding" "firewall" "forwardPairs" ]
        ];
      })
    )
  );
in
if fromRules != [ ] then fromRules else fromPairs
